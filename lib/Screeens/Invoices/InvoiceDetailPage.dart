import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Services/invoice_print_ui.dart';
import '../../Services/invoice_special_service.dart';
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
  late bool _isSpecial;
  bool _togglingSpecial = false;
  bool _reloadInProgress = false;
  bool _notifyParentOnPop = false;
  late Map<String, dynamic> _invoice;

  Map<String, dynamic> get invoice => _invoice;

  String get _rootInvoiceId =>
      SalesInvoiceActionsService.rootInvoiceIdFrom(invoice);

  String get _clientId => invoice['clientName']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _invoice = Map<String, dynamic>.from(widget.invoice);
    _isSpecial = InvoiceSpecialService.isSpecial(_invoice);
    _loadUserRole();
  }

  Future<void> _reloadInvoiceFromFirestore() async {
    if (_rootInvoiceId.isEmpty) return;
    setState(() => _reloadInProgress = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_sourceCollection)
          .doc(_rootInvoiceId)
          .get();
      if (!doc.exists || !mounted) return;
      final data = Map<String, dynamic>.from(doc.data()!);
      data['id'] = doc.id;
      data['_sourceCollection'] = _sourceCollection;
      setState(() {
        _invoice = data;
        _isSpecial = InvoiceSpecialService.isSpecial(data);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث بيانات الفاتورة: $e')),
      );
    } finally {
      if (mounted) setState(() => _reloadInProgress = false);
    }
  }

  String get _sourceCollection =>
      InvoiceSpecialService.sourceCollection(invoice);

  Future<void> _toggleSpecial() async {
    if (_rootInvoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرّف الفاتورة غير متوفر')),
      );
      return;
    }
    setState(() => _togglingSpecial = true);
    final next = !_isSpecial;
    try {
      await InvoiceSpecialService.setSpecial(
        collection: _sourceCollection,
        docId: _rootInvoiceId,
        clientName: _clientId,
        special: next,
      );
      if (!mounted) return;
      setState(() {
        _isSpecial = next;
        invoice['isSpecial'] = next;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next ? 'تم تمييز الفاتورة كمميزة' : 'تم إلغاء تمييز الفاتورة',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _togglingSpecial = false);
    }
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

    final editPayload = await SalesInvoiceActionsService.buildEditPayload(
      invoice,
      clientSubDocId: invoice['_clientSubDocId']?.toString(),
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DecreaseProductPage(invoiceToEdit: editPayload),
      ),
    );
    if (changed == true && mounted) {
      await _reloadInvoiceFromFirestore();
      if (!mounted) return;
      setState(() => _notifyParentOnPop = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث عرض الفاتورة')),
      );
    }
  }

  void _popToParent() {
    Navigator.pop(context, _notifyParentOnPop || _deleted);
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popToParent();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _popToParent,
        ),
        automaticallyImplyLeading: false,
        title: Text(
          '#${invoice['invoiceNumber']}',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          IconButton(
            tooltip: _isSpecial ? 'إلغاء التمييز' : 'تمييز كفاتورة مميزة',
            onPressed: _togglingSpecial ? null : _toggleSpecial,
            icon: _togglingSpecial
                ? SizedBox(
                    width: 22.w,
                    height: 22.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  )
                : Icon(
                    _isSpecial ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 26.sp,
                  ),
          ),
          InvoiceActionButtons(
            showEditDelete: _isAdmin,
            onPrint: _print,
            onShare: _share,
            onEdit: _edit,
            onDelete: _delete,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding:
                      EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
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
              ],
            ),
          ),
          if (_reloadInProgress)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.orange),
              ),
            ),
        ],
      ),
    ),
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
