import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Services/invoice_print_ui.dart';
import '../../Services/sales_invoice_actions_service.dart';
import '../../Services/whatsapp_invoice_share_service.dart';
import '../../Widgets/invoice_action_buttons.dart';
import '../../Widgets/invoice_display_widgets.dart';
import '../DecreaseProductPage.dart';

class InvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoice;

  const InvoiceDetailPage({super.key, required this.invoice});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  String _userRole = 'user';
  bool _deleted = false;

  Map<String, dynamic> get invoice => widget.invoice;

  String get _rootInvoiceId =>
      invoice['id']?.toString() ?? invoice['invoiceId']?.toString() ?? '';

  String get _clientId => invoice['clientName']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userRole = prefs.getString('user_role') ?? 'user';
    });
  }

  bool get _isAdmin => _userRole == 'admin';

  Future<void> _print() async {
    await InvoicePrintUi.printInvoice(
      context,
      invoice,
      clientId: _clientId.isNotEmpty ? _clientId : null,
    );
  }

  Future<void> _share() async {
    await WhatsappInvoiceShareService.showShareOptions(
      context,
      invoice: invoice,
    );
  }

  Future<void> _edit() async {
    if (!_isAdmin) {
      _permissionDenied();
      return;
    }
    if (_clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد عميل مرتبط بهذه الفاتورة')),
      );
      return;
    }
    if (_rootInvoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرّف الفاتورة غير متوفر للتعديل')),
      );
      return;
    }

    final editPayload = Map<String, dynamic>.from(invoice);
    editPayload['id'] = _rootInvoiceId;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DecreaseProductPage(invoiceToEdit: editPayload),
      ),
    );
    if (changed == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    if (!_isAdmin) {
      _permissionDenied();
      return;
    }
    if (_rootInvoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرّف الفاتورة غير متوفر للحذف')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد أنك تريد حذف هذه الفاتورة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await SalesInvoiceActionsService.deleteSalesInvoice(
        invoice: invoice,
        rootInvoiceId: _rootInvoiceId,
      );
      if (!mounted) return;
      setState(() => _deleted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفاتورة بنجاح')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الحذف: $e')),
      );
    }
  }

  void _permissionDenied() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ليس لديك صلاحية'),
        content: const Text('ليس لديك الصلاحية لهذا الإجراء'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    final products = invoice['products'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'رقم الفاتورة #${invoice['invoiceNumber']}',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          InvoiceActionButtons(
            showEditDelete: _isAdmin,
            onPrint: _print,
            onShare: _share,
            onEdit: _edit,
            onDelete: _delete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/boxes_11365317.png',
                      width: 200.w,
                      height: 80.h,
                      fit: BoxFit.fill,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Center(
                    child: Text(
                      'فاتورة مبيعات',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  _partyHeader(
                    label: 'اسم العميل',
                    name: _clientId,
                  ),
                  SizedBox(height: 10.h),
                  InvoiceProductsTable(products: products),
                  InvoiceTotalsFooter(invoice: invoice),
                ],
              ),
            ),
        
              
        ]),)
    );
  }

  Widget _partyHeader({required String label, required String name}) {
    final when = InvoiceDateParts.fromDynamic(invoice['date']);
    return Row(
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
                    text: 'رقم الفاتورة: ',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: '#${invoice['invoiceNumber']}',
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
                    TextSpan(text: when.time, style: TextStyle(fontSize: 13.sp)),
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
                    text: '$label: ',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(text: name, style: TextStyle(fontSize: 13.sp)),
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
                    TextSpan(text: when.date, style: TextStyle(fontSize: 13.sp)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
