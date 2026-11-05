import '../repositories/client_repository.dart';
import '../utils/entity_name_normalizer.dart';
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
    // Keep the invoice's own customer ID unless the user picked another
    // customer. A name lookup alone could match a different customer that
    // shares the name, moving the balance to the wrong account.
    final originalClientId =
        originalInvoice['clientId']?.toString().trim() ?? '';
    final sameCustomer = originalClientId.isNotEmpty &&
        ClientRepository.instance.getById(originalClientId) != null &&
        normalizeEntityName(clientName) ==
            normalizeEntityName(
                originalInvoice['clientName']?.toString() ?? '');
    final saved = await CustomerOperationService.saveInvoice({
      ...originalInvoice,
      'id': rootInvoiceId,
      'invoiceId': rootInvoiceId,
      'clientId': sameCustomer
          ? originalClientId
          : ClientRepository.instance.findByName(clientName)?.id ??
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
