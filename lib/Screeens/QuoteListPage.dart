import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;

import '../Services/invoice_number_utils.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/quote_execution_service.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import 'DecreaseProductPage.dart';

class QuoteListPage extends StatelessWidget {
  const QuoteListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.80),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          'عروض الأسعار',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('عرض سعر جديد', style: TextStyle(fontSize: 13.sp)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const DecreaseProductPage(isQuote: true)),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('price_quotes')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 64.sp, color: Colors.black26),
                  SizedBox(height: 16.h),
                  Text(
                    'لا توجد عروض أسعار',
                    style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.black45,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 90.h),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              return _QuoteCard(
                quoteId: doc.id,
                data: doc.data(),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quote Card (Collapsible, Editable, Sharable)
// ─────────────────────────────────────────────────────────────────────────────

class _QuoteCard extends StatefulWidget {
  final String quoteId;
  final Map<String, dynamic> data;

  const _QuoteCard({required this.quoteId, required this.data});

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  bool _isExpanded = false;
  bool _executing = false;
  bool _deleting = false;

  String _dateStr() {
    final d = widget.data['date'];
    DateTime? dt;
    if (d is Timestamp) dt = d.toDate().toLocal();
    if (d is DateTime) dt = d.toLocal();
    if (dt == null) return '';
    return intl.DateFormat('yyyy/MM/dd').format(dt);
  }

  String _timeStr() {
    final d = widget.data['date'];
    DateTime? dt;
    if (d is Timestamp) dt = d.toDate().toLocal();
    if (d is DateTime) dt = d.toLocal();
    if (dt == null) return '';
    return intl.DateFormat('hh:mm a').format(dt);
  }

  Future<void> _editQuote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DecreaseProductPage(
          isQuote: true,
          invoiceToEdit: widget.data,
        ),
      ),
    );
  }

  Future<void> _execute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
          title: const Text('تأكيد التنفيذ'),
          content: const Text(
              'هل تريد تنفيذ عرض السعر هذا كفاتورة مبيعات؟\nسيتم حذف العرض بعد التنفيذ.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تنفيذ'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _executing = true);
    try {
      final clientName = widget.data['clientName']?.toString() ?? '';
      double prevBalance = 0.0;
      if (clientName.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('clients')
            .where('clientName', isEqualTo: clientName)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          prevBalance = invoiceNum(q.docs.first.data()['balance']);
        }
      }

      final invoice = await QuoteExecutionService.executeQuote(
        quoteId: widget.quoteId,
        quoteData: widget.data,
        previousClientBalance: prevBalance,
      );

      if (!mounted) return;
      _showSuccessDialog(invoice);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء التنفيذ: $e')),
      );
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
          title: const Text('حذف عرض السعر'),
          content: const Text('هل تريد حذف عرض السعر هذا نهائياً؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await FirebaseFirestore.instance
          .collection('price_quotes')
          .doc(widget.quoteId)
          .delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء الحذف: $e')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showSuccessDialog(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
          title: Text('تم التنفيذ بنجاح',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _infoLine('رقم الفاتورة', '#${invoice['invoiceNumber']}'),
                _infoLine('العميل', invoice['clientName']?.toString() ?? ''),
                _infoLine('الإجمالي',
                    '${invoiceAmount(invoice['totalSum'])} ج.م'),
                _infoLine('المدفوع',
                    '${invoiceAmount(invoice['paidAmount'])} ج.م'),
                SizedBox(height: 16.h),
                ElevatedButton.icon(
                  onPressed: () {
                    InvoicePrintUi.printInvoice(ctx, invoice,
                        clientId: invoice['clientName']?.toString());
                  },
                  icon: const Icon(Icons.print, color: Colors.white),
                  label: const Text('طباعة الفاتورة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                  ),
                ),
                SizedBox(height: 8.h),
                ElevatedButton.icon(
                  onPressed: () {
                    WhatsappInvoiceShareService.showShareOptions(ctx,
                        invoice: invoice);
                  },
                  icon: const Icon(Icons.chat, color: Colors.white),
                  label: const Text('مشاركة في واتساب'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                  ),
                ),
                SizedBox(height: 8.h),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('إنهاء'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: TextStyle(fontSize: 13.sp, color: Colors.black54))),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.left,
                style:
                    TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTable(List<dynamic> products) {
    final rows = products
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: const Text(
          'لا توجد منتجات في عرض السعر',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    var qtySum = 0.0;
    for (final p in rows) {
      qtySum += double.tryParse(p['amount']?.toString() ?? '') ?? 0;
    }

    Widget cell(
      String text, {
      bool bold = false,
      TextAlign align = TextAlign.center,
    }) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
        child: Text(
          text,
          textAlign: align,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    final hasAnyDiscount = rows.any(
      (p) => ((p['discount'] as num?)?.toDouble() ?? 0.0) > 0,
    );

    if (!hasAnyDiscount) {
      return Table(
        border: TableBorder.all(color: Colors.grey.shade400, width: 0.8),
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(1.1),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.2),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: [
              cell('اسم المنتج', bold: true, align: TextAlign.right),
              cell('الكمية', bold: true),
              cell('السعر', bold: true),
              cell('الإجمالي', bold: true),
            ],
          ),
          for (final p in rows)
            TableRow(
              decoration:
                  BoxDecoration(color: Colors.orange.withOpacity(0.12)),
              children: [
                cell(invoiceProductName(p), align: TextAlign.right),
                cell(invoiceQty(p['amount'])),
                cell(invoiceAmount(p['selectedPrice'] ?? p['price'])),
                cell(invoiceAmount(p['total'])),
              ],
            ),
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              cell(''),
              cell(invoiceQty(qtySum), bold: true),
              cell(''),
              cell(''),
            ],
          ),
        ],
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade400, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.1),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.2),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            cell('اسم المنتج', bold: true, align: TextAlign.right),
            cell('الكمية', bold: true),
            cell('السعر', bold: true),
            cell('الخصم', bold: true),
            cell('الإجمالي', bold: true),
          ],
        ),
        for (final p in rows)
          TableRow(
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12)),
            children: [
              cell(invoiceProductName(p), align: TextAlign.right),
              cell(invoiceQty(p['amount'])),
              cell(invoiceAmount(p['selectedPrice'] ?? p['price'])),
              cell(invoiceAmount(p['discount'] ?? 0)),
              cell(invoiceAmount(p['total'])),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            cell(''),
            cell(invoiceQty(qtySum), bold: true),
            cell(''),
            cell(''),
            cell(''),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientName = widget.data['clientName']?.toString() ?? 'بدون اسم';
    final totalSum = invoiceNum(widget.data['totalSum']);
    final paidAmount = invoiceNum(widget.data['paidAmount']);
    final previousBalance = invoiceDynamicPreviousBalance(widget.data);
    final invoiceDiscount = invoiceResolveDiscount(widget.data);
    final invoiceRemaining = totalSum - paidAmount;
    final remainingOwed = previousBalance + invoiceRemaining;

    final products = (widget.data['products'] as List? ?? []);

    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(10.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    borderRadius: BorderRadius.circular(6.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 20.sp,
                            color: Colors.orange.shade800,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  clientName,
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  'إجمالي العرض: ${invoiceAmount(totalSum)} ج.م',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.orange.shade800,
                            size: 24.sp,
                          ),
                          SizedBox(width: 6.w),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Toolbar Actions ────────────────────────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.print_outlined,
                          color: Colors.black87),
                      tooltip: 'طباعة',
                      onPressed: () => InvoicePrintUi.printInvoice(
                        context,
                        widget.data,
                        clientId: clientName.isNotEmpty ? clientName : null,
                      ),
                    ),
                    IconButton(
                      icon: FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Colors.green.shade700,
                        size: 20.sp,
                      ),
                      tooltip: 'مشاركة في واتساب',
                      onPressed: () =>
                          WhatsappInvoiceShareService.showShareOptions(
                        context,
                        invoice: widget.data,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      tooltip: 'تعديل عرض السعر',
                      onPressed: _editQuote,
                    ),
                    IconButton(
                      icon: _deleting
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'حذف',
                      onPressed: _deleting ? null : _delete,
                    ),
                    SizedBox(width: 4.w),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r)),
                      ),
                      onPressed: _executing ? null : _execute,
                      icon: _executing
                          ? SizedBox(
                              width: 14.w,
                              height: 14.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.play_circle_outline, size: 16.sp),
                      label: Text('تنفيذ',
                          style: TextStyle(
                              fontSize: 12.sp, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),

            // ── Expanded Content ──────────────────────────────────────────
            if (_isExpanded) ...[
              Divider(height: 16.h, color: Colors.grey.shade300),
              Row(
                children: [
                  Text('التاريخ: ${_dateStr()}',
                      style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                  SizedBox(width: 16.w),
                  Text('الوقت: ${_timeStr()}',
                      style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                ],
              ),
              if (widget.data['notes'] != null &&
                  widget.data['notes'].toString().trim().isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text('ملاحظات: ${widget.data['notes']}',
                    style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
              ],
              SizedBox(height: 10.h),

              // ── Products Table ──────────────────────────────────────────
              _buildProductsTable(products),

              // ── Summary Footer ──────────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(top: 10.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'الرصيد السابق: ${invoiceAmount(previousBalance)}',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 16.w),
                            Text(
                              'إجمالي الفاتورة: ${invoiceAmount(totalSum)}',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (invoiceDiscount > 0)
                          Padding(
                            padding: EdgeInsets.only(top: 2.h),
                            child: Text(
                              'خصم الفاتورة: ${invoiceAmount(invoiceDiscount)}',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            'المدفوع: ${invoiceAmount(paidAmount)}',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            'المتبقي من الفاتورة: ${invoiceAmount(invoiceRemaining)}',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            'المتبقي عليكم: ${invoiceAmount(remainingOwed)}',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


