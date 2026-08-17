import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/quote_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';

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

    // 1. Resolve client id locally from Hive
    var client = ClientRepository.instance.findByName(clientName);
    String clientId;
    if (client != null) {
      clientId = client.id;
    } else {
      clientId = quoteData['clientId']?.toString() ?? _uuid.v4();
      await ClientRepository.instance.upsertLocal(clientId, {
        'clientName': clientName,
        'balance': 0.0,
        'id': clientId,
      });
      await SyncQueueManager.instance.enqueue(
        operationType: 'createClient',
        payload: {
          'clientId': clientId,
          'data': {'clientName': clientName, 'balance': 0.0},
          'openingBalance': 0.0,
        },
      );
    }

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
    final updatedBalance = previousClientBalance + balance;
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

    // 5. Persist to Hive (Primary DB)
    await InvoiceRepository.instance.upsertSaleLocal(invoiceDocId, invoiceData);
    await ClientRepository.instance.updateLocalBalance(clientId, updatedBalance);
    if (paidAmount > 0) {
      await BoxRepository.instance.increment(paidAmount);
    }
    await InvoiceStockService.applyStockChanges(
      lines: lines,
      restore: false,
      changeDate: date,
      catalog: catalog,
    );

    // Delete quote locally
    await QuoteRepository.instance.deleteLocal(quoteId);

    // Balance history entries locally
    final hist1Id = _uuid.v4();
    await BalanceHistoryRepository.instance.upsertLocal(
      BalanceHistoryLocal(
        id: hist1Id,
        parentId: clientId,
        parentType: 'client',
        enteredBalance: totalSumFinal,
        balanceBefore: previousClientBalance,
        type: 'sale',
        invoiceId: invoiceDocId,
        invoiceNumber: newInvoiceNumber.toString(),
        timestamp: date,
      ),
    );

    if (paidAmount > 0) {
      final hist2Id = _uuid.v4();
      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: hist2Id,
          parentId: clientId,
          parentType: 'client',
          enteredBalance: paidAmount,
          balanceBefore: previousClientBalance + totalSumFinal,
          type: 'sale_payment',
          invoiceId: invoiceDocId,
          invoiceNumber: newInvoiceNumber.toString(),
          timestamp: date,
        ),
      );
    }

    // 6. Enqueue operations for background Firestore sync
    await SyncQueueManager.instance.enqueue(
      operationType: 'createInvoice',
      payload: {
        'clientId': clientId,
        'invoiceId': invoiceDocId,
        'invoiceData': invoiceData,
        'products': lines,
        'totalSum': totalSumFinal,
        'paidAmount': paidAmount,
      },
    );

    await SyncQueueManager.instance.enqueue(
      operationType: 'deleteQuote',
      payload: {
        'quoteId': quoteId,
      },
    );

    // Trigger sync in background
    ConnectivityService.instance.forceSync();

    return invoiceData;
  }
}
