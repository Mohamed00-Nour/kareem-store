import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../Services/invoice_number_utils.dart';
import '../../Services/invoice_special_service.dart';
import 'InvoiceDetailPage.dart';

/// Lists sales and return invoices marked as special (مميزة).
class SpecialInvoicesPage extends StatefulWidget {
  const SpecialInvoicesPage({super.key});

  @override
  State<SpecialInvoicesPage> createState() => _SpecialInvoicesPageState();
}

class _SpecialInvoicesPageState extends State<SpecialInvoicesPage> {
  final List<Map<String, dynamic>> _invoices = [];
  final List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _isFetching = true);
    try {
      final list = await InvoiceSpecialService.fetchSpecialInvoices();
      if (!mounted) return;
      setState(() {
        _invoices
          ..clear()
          ..addAll(list);
        _applyFilter();
        _isFetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFetching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل الفواتير: $e')),
      );
    }
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered
        ..clear()
        ..addAll(_invoices.where((inv) {
          if (q.isEmpty) return true;
          final client = inv['clientName']?.toString().toLowerCase() ?? '';
          final num = inv['invoiceNumber']?.toString() ?? '';
          return client.contains(q) || num.contains(q);
        }));
    });
  }

  String _formatDate(dynamic date) {
    DateTime? dt;
    if (date is Timestamp) dt = date.toDate();
    if (date is DateTime) dt = date;
    if (dt == null) return '';
    return DateFormat('yyyy-MM-dd').format(dt.toLocal());
  }

  Future<void> _openDetail(Map<String, dynamic> invoice) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(invoice: invoice),
      ),
    );
    if (changed == true) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: Text(
          'الفواتير المميزة',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetch,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
            child: TextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'ابحث برقم الفاتورة أو اسم العميل...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isFetching
                ? Center(
                    child: CircularProgressIndicator(
                      color: Colors.orange.withOpacity(0.85),
                    ),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد فواتير مميزة',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Colors.black54,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final gap = 8.w;
                            final cardWidth =
                                (constraints.maxWidth - gap * 3) / 2;
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                  gap, 4.h, gap, 12.h),
                              child: Wrap(
                                spacing: gap,
                                runSpacing: 8.h,
                                children: [
                                  for (final invoice in _filtered)
                                    SizedBox(
                                      width: cardWidth,
                                      child: _SpecialInvoiceGridCard(
                                        invoice: invoice,
                                        dateLabel:
                                            _formatDate(invoice['date']),
                                        onTap: () => _openDetail(invoice),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _SpecialInvoiceGridCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String dateLabel;
  final VoidCallback onTap;

  const _SpecialInvoiceGridCard({
    required this.invoice,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isReturn = InvoiceSpecialService.sourceCollection(invoice) ==
        InvoiceSpecialService.returnCollection;
    final total = invoiceNum(invoice['totalSum']);
    final paid = invoiceNum(invoice['paidAmount']);
    final invoiceRemainder = invoiceUnpaidAmount(invoice);
    final previous = invoiceDynamicPreviousBalance(invoice);
    final balanceAfter = invoiceClientRemainingOwed(invoice);
    final balanceDiff = balanceAfter - previous;

    return Material(
      color: Colors.amber.shade50,
      elevation: 2,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.star, color: Colors.amber.shade800, size: 18.sp),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      '#${invoice['invoiceNumber']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.sp,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 5.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: isReturn ? Colors.red.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      InvoiceSpecialService.typeLabel(invoice),
                      style: TextStyle(
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                        color: isReturn
                            ? Colors.red.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                invoice['clientName']?.toString() ?? '',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.sp, color: Colors.black87),
              ),
              if (dateLabel.isNotEmpty)
                Text(
                  dateLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10.sp, color: Colors.black54),
                ),
              SizedBox(height: 6.h),
              const Divider(height: 1),
              SizedBox(height: 4.h),
              _amountRow('إجمالي الفاتورة', total),
              _amountRow('المدفوع', paid, valueColor: Colors.green.shade700),
              _amountRow(
                'المتبقي من الفاتورة',
                invoiceRemainder,
                valueColor: invoiceRemainder > 0
                    ? Colors.orange.shade800
                    : Colors.black87,
              ),
              _amountRow(
                'المتبقي عليكم',
                balanceAfter,
                valueColor: balanceAfter > 0
                    ? Colors.red.shade700
                    : Colors.black87,
                bold: true,
              ),
              _amountRow('الرصيد السابق', previous),
              _amountRow(
                'الفرق (بعد − قبل)',
                balanceDiff,
                valueColor: balanceDiff > 0
                    ? Colors.red.shade700
                    : balanceDiff < 0
                        ? Colors.green.shade700
                        : Colors.black87,
                bold: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountRow(
    String label,
    double value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.h),
      child: Row(
        children: [
          Text(
            '${invoiceAmount(value)} ج.م',
            style: TextStyle(
              fontSize: bold ? 11.sp : 10.sp,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 2,
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5.sp,
                color: Colors.black54,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
