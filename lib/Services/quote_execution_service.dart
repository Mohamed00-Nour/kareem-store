import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../repositories/client_repository.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'customer_operation_service.dart';
import 'quick_entity_creation_service.dart';

/// Converts a saved price-quote document into a real sales invoice locally first,
/// then pushes changes to Firestore in the background.
class QuoteExecutionService {
  QuoteExecutionService._();
  static const _uuid = Uuid();

  /// Execute [quoteId] / [quoteData] as a real sales invoice.
  static Future<Map<String, dynamic>> executeQuote({
    required String quoteId,
    required Map<String, dynamic> quoteData,
    required double previousClientBalance,
  }) async {
    final clientName = quoteData['clientName']?.toString() ?? '';
    final lines = List<Map<String, dynamic>>.from(
        (quoteData['products'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    final totalSumBeforeDiscount =
        lines.fold<double>(0.0, (acc, p) => acc + invoiceNum(p['total']));

    final invoiceDiscount = invoiceNum(quoteData['invoiceDiscount']);
    final discountIsPercent =
        (quoteData['discountIsPercent'] as bool?) ?? false;

    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;

    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;
    final paidAmount = invoiceNum(quoteData['paidAmount']);
    final paymentMethod = quoteData['paymentMethod']?.toString() ?? 'نقداً';
    final notes = quoteData['notes']?.toString() ?? '';

    final date = () {
      final d = quoteData['date'];
      if (d is Timestamp) return d.toDate();
      if (d is DateTime) return d;
      return DateTime.now();
    }();

    var client = ClientRepository.instance.findByName(clientName);
    client ??= await QuickEntityCreationService.instance
        .createClient(name: clientName);
    final clientId = client.id;

    // 2. Fetch next sequential invoice number locally
    final newInvoiceNumber = LocalInvoiceCounter.nextNumber('sale');

    // 3. Resolve catalog & costs locally
    final catalog = await InvoiceStockService.resolveCatalogIfNeeded(
      lines: lines,
      seed: const {},
    );

    final totalCost = InvoiceStockService.computeCostTotal(lines, catalog);
    final profitMargin = totalSumFinal - totalCost;
    final balance = totalSumFinal - paidAmount;
    final invoiceDocId = _uuid.v4();

    // 4. Build invoice document
    final invoiceData = <String, dynamic>{
      'id': invoiceDocId,
      'invoiceId': invoiceDocId,
      'invoiceNumber': newInvoiceNumber,
      'clientName': clientName,
      'clientId': clientId,
      'date': date,
      'totalSum': totalSumFinal,
      'profitMargin': profitMargin,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousClientBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': effectiveDiscountAmt,
      'invoiceType': 'sale',
      'isSpecial': false,
      'products': lines,
    };

    final saved = await CustomerOperationService.saveInvoice(invoiceData,
        quoteId: quoteId);

    // Trigger sync in background
    ConnectivityService.instance.forceSync();

    return saved;
  }
}
