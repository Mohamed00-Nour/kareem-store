import 'invoice_number_utils.dart';
import 'supplier_operation_service.dart';

/// Compatibility entry point used by the purchase editor.
class BuyingInvoiceUpdateService {
  static Future<void> updateBuyingInvoice({
    required String rootInvoiceId,
    required Map<String, dynamic> originalInvoice,
    required List<Map<String, dynamic>> newProducts,
    required String supplierName,
    required String supplierId,
    required DateTime? selectedDate,
    required double paidAmount,
    required String notes,
    required double invoiceDiscount,
  }) async {
    final totalBeforeDiscount = newProducts.fold<double>(
        0, (sum, line) => sum + invoiceNum(line['totalCost']));
    await SupplierOperationService.saveBuyingInvoice({
      ...originalInvoice,
      'id': rootInvoiceId,
      'invoiceId': rootInvoiceId,
      'supplierName': supplierName,
      'supplierId': supplierId,
      'date': selectedDate ?? DateTime.now(),
      'totalSum': totalBeforeDiscount - invoiceDiscount,
      'paidAmount': paidAmount,
      'invoiceDiscount': invoiceDiscount,
      'notes': notes,
      'products': newProducts,
    }, editing: true);
  }
}
