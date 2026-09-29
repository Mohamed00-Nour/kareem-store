import '../repositories/client_repository.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'customer_operation_service.dart';

/// Updates an existing sales invoice locally in Hive first, then syncs to Firestore in background.
class SalesInvoiceUpdateService {
  static Future<double> productCostTotal(
      List<Map<String, dynamic>> products) async {
    return InvoiceStockService.computeCostTotalAsync(products);
  }

  static Future<Map<String, dynamic>> updateSalesInvoice({
    required String rootInvoiceId,
    String? clientSubInvoiceDocId,
    required Map<String, dynamic> originalInvoice,
    required List<Map<String, dynamic>> newProducts,
    required String clientName,
    required DateTime? selectedDate,
    required double paidAmount,
    required String paymentMethod,
    required String notes,
    required double invoiceDiscount,
    required bool discountIsPercent,
    required double totalSumBeforeDiscount,
    String? sourceCollection,
  }) async {
    final discount = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    final saved = await CustomerOperationService.saveInvoice({
      ...originalInvoice,
      'id': rootInvoiceId,
      'invoiceId': rootInvoiceId,
      'clientId': ClientRepository.instance.findByName(clientName)?.id ??
          originalInvoice['clientId'],
      'clientName': clientName,
      'date': selectedDate ?? DateTime.now(),
      'paidAmount': paidAmount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'totalSum': totalSumBeforeDiscount - discount,
      'invoiceDiscount': discount,
      'products': newProducts,
    },
        editing: true,
        isReturn: sourceCollection == 'returnInvoices' ||
            invoiceIsReturn(originalInvoice),
        clientSubDocId: clientSubInvoiceDocId);
    ConnectivityService.instance.forceSync();
    return saved;
  }
}
