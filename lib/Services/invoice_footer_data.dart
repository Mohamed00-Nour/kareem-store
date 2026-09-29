import 'invoice_number_utils.dart';
import 'sales_invoice_actions_service.dart';

/// Both customer and sales pages render these rows, from the same Hive view.
class InvoiceFooterData {
  final double previous, total, paid, remaining, discount;
  final bool supplier;
  const InvoiceFooterData(this.previous, this.total, this.paid, this.remaining,
      this.discount, this.supplier);

  factory InvoiceFooterData.fromInvoice(Map<String, dynamic> raw) {
    final supplier = invoiceIsSupplierPurchase(raw);
    final invoice =
        supplier ? raw : SalesInvoiceActionsService.buildClientPagePayload(raw);
    return InvoiceFooterData(
        invoiceDynamicPreviousBalance(invoice),
        invoiceNum(invoice['totalSum']),
        invoiceNum(invoice['paidAmount']),
        invoiceBalanceAfter(invoice),
        invoiceResolveDiscount(invoice),
        supplier);
  }

  List<String> get rows => [
        'الرصيد السابق: ${invoiceAmount(previous)}',
        'إجمالي الفاتورة: ${invoiceAmount(total)}',
        if (discount > 0) 'خصم الفاتورة: ${invoiceAmount(discount)}',
        'المدفوع: ${invoiceAmount(paid)}',
        '${supplier ? 'المتبقي للمورد' : 'المتبقي عليكم'}: ${invoiceAmount(remaining)}',
      ];
}
