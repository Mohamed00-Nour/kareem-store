import 'package:uuid/uuid.dart';
import '../repositories/client_repository.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'customer_operation_service.dart';
import 'quick_entity_creation_service.dart';

/// Persists a return invoice: restores stock, updates client & box locally first,
/// then pushes to Firestore in the background.
class ReturnInvoiceSaveService {
  static const _uuid = Uuid();

  static Future<Map<String, dynamic>> save({
    required String clientName,
    required DateTime? selectedDate,
    required List<Map<String, dynamic>> products,
    required double paidAmount,
    required String paymentMethod,
    required String notes,
    required double invoiceDiscount,
    required bool discountIsPercent,
    required double previousBalanceSnapshot,
    required double totalSumBeforeDiscount,
    required Future<double> Function(List<Map<String, dynamic>> products)
        calculateTotalCost,
    Map<String, ResolvedInvoiceProduct> productCatalog = const {},
  }) async {
    final discount = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    var client = ClientRepository.instance.findByName(clientName);
    client ??= await QuickEntityCreationService.instance
        .createClient(name: clientName);
    final saved = await CustomerOperationService.saveInvoice({
      'id': _uuid.v4(),
      'clientId': client.id,
      'clientName': client.name,
      'invoiceNumber': LocalInvoiceCounter.nextNumber('return'),
      'date': selectedDate ?? DateTime.now(),
      'totalSum': totalSumBeforeDiscount - discount,
      'paidAmount': paidAmount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': discount,
      'products': products,
    }, isReturn: true);
    ConnectivityService.instance.forceSync();
    return saved;
  }
}
