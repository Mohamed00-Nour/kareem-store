import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/invoice_number_utils.dart';
import '../Services/supplier_invoice_running_balance_service.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import '../Screeens/AddProductPage.dart';
import '../Widgets/invoice_action_buttons.dart';
import '../Widgets/invoice_display_widgets.dart';

class BuyingInvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoice;

  const BuyingInvoiceDetailPage({super.key, required this.invoice});

  @override
  State<BuyingInvoiceDetailPage> createState() =>
      _BuyingInvoiceDetailPageState();
}

class _BuyingInvoiceDetailPageState extends State<BuyingInvoiceDetailPage> {
  bool get _isReturn => invoiceIsBuyingReturn(widget.invoice);

  Future<void> _openEdit() async {
    if (_isReturn) {
      // Editing a purchase return changes stock, payable and cash: admins only.
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if ((prefs.getString('user_role') ?? 'user') != 'admin') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ليس لديك الصلاحية لتعديل المرتجع')));
        return;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(invoiceToEdit: widget.invoice),
      ),
    );
  }

  /// Same WhatsApp share sheet as the sales invoice page (recipient choice,
  /// text or image), using the balances shown on this page.
  Future<void> _share(Map<String, dynamic> invoiceData) async {
    await WhatsappInvoiceShareService.showShareOptions(
      context,
      invoice: invoiceData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceData =
        SupplierInvoiceRunningBalanceService.buildPayload(widget.invoice);

    final products = invoiceData['products'] as List<dynamic>? ?? [];
    final when = InvoiceDateParts.fromDynamic(invoiceData['date']);
    final supplierName = invoiceData['supplierName']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_isReturn ? 'رقم المرتجع' : 'رقم الفاتورة'} #${invoiceData['invoiceNumber']}',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor:
            _isReturn ? Colors.red.shade900 : Colors.black.withOpacity(0.7),
        actions: [
          InvoiceActionButtons(
            onShare: () => _share(invoiceData),
            onEdit: _openEdit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/boxes_11365317.png',
                        width: 200.w,
                        height: 100.h,
                        fit: BoxFit.fill,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Center(
                      child: Text(
                        _isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _isReturn
                                        ? 'رقم المرتجع: '
                                        : 'رقم الفاتورة: ',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '#${invoiceData['invoiceNumber']}',
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            if (when.time.isNotEmpty) ...[
                              SizedBox(height: 5.h),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: when.time,
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                    TextSpan(
                                      text: ' :الوقت',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'اسم المورد: ',
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: supplierName,
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ],
                              ),
                            ),
                            if (when.date.isNotEmpty) ...[
                              SizedBox(height: 5.h),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'التاريخ: ',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: when.date,
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    InvoiceProductsTable(
                      products: products,
                      kind: InvoiceDisplayKind.purchase,
                    ),
                    InvoiceTotalsFooter(
                      invoice: invoiceData,
                      remainingLabel: 'المتبقي عليكم',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
