import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;

  Map<String, double>? _result;
  double? _buyingTotal;

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: _datePickerTheme,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _fetchReport() async {
    if (_startDate == null || _endDate == null) return;
    setState(() => _loading = true);

    final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);

    try {
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      double totalSales = 0;
      double totalProfit = 0;
      double totalPaid = 0;
      double totalBalance = 0;
      int invoiceCount = 0;

      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        totalSales += (data['totalSum'] ?? 0.0).toDouble();
        totalProfit += (data['profitMargin'] ?? 0.0).toDouble();
        totalPaid += (data['paidAmount'] ?? 0.0).toDouble();
        totalBalance += (data['balance'] ?? 0.0).toDouble();
        invoiceCount++;
      }

      final buyingSnap = await FirebaseFirestore.instance
          .collection('buying invoices')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      double buyingTotal = 0;
      for (final doc in buyingSnap.docs) {
        buyingTotal += (doc.data()['totalSum'] ?? 0.0).toDouble();
      }

      setState(() {
        _result = {
          'totalSales': totalSales,
          'totalProfit': totalProfit,
          'totalPaid': totalPaid,
          'totalBalance': totalBalance,
          'invoiceCount': invoiceCount.toDouble(),
        };
        _buyingTotal = buyingTotal;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'تقرير المبيعات',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            children: [
              _DateRangeSelector(
                startDate: _startDate,
                endDate: _endDate,
                onPickStart: () => _pickDate(true),
                onPickEnd: () => _pickDate(false),
              ),
              SizedBox(height: 14.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.85),
                    foregroundColor: Colors.black.withOpacity(0.8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                  onPressed:
                      (_startDate != null && _endDate != null && !_loading)
                          ? _fetchReport
                          : null,
                  child: _loading
                      ? SizedBox(
                          width: 20.w,
                          height: 20.h,
                          child: const CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black54),
                        )
                      : Text('عرض التقرير',
                          style: TextStyle(
                              fontSize: 16.sp, fontWeight: FontWeight.bold)),
                ),
              ),
              if (_result != null) ...[
                SizedBox(height: 20.h),
                _SummaryCard(
                  title: 'ملخص الفترة',
                  color: Colors.orange,
                  children: [
                    _SummaryRow(
                        label: 'عدد الفواتير',
                        value: '${_result!['invoiceCount']!.toInt()}',
                        unit: 'فاتورة'),
                    _SummaryRow(
                        label: 'إجمالي المبيعات',
                        value: _result!['totalSales']!.toStringAsFixed(2),
                        unit: 'ج.م'),
                    _SummaryRow(
                        label: 'إجمالي الأرباح',
                        value: _result!['totalProfit']!.toStringAsFixed(2),
                        unit: 'ج.م',
                        highlight: true),
                    _SummaryRow(
                        label: 'المبالغ المحصلة',
                        value: _result!['totalPaid']!.toStringAsFixed(2),
                        unit: 'ج.م'),
                    _SummaryRow(
                        label: 'الديون المتبقية',
                        value: _result!['totalBalance']!.toStringAsFixed(2),
                        unit: 'ج.م',
                        isDebt: true),
                  ],
                ),
                SizedBox(height: 12.h),
                _SummaryCard(
                  title: 'المشتريات',
                  color: Colors.blue,
                  children: [
                    _SummaryRow(
                        label: 'إجمالي المشتريات',
                        value: _buyingTotal!.toStringAsFixed(2),
                        unit: 'ج.م'),
                  ],
                ),
                SizedBox(height: 12.h),
                _SummaryCard(
                  title: 'صافي الربح',
                  color: Colors.green,
                  children: [
                    _SummaryRow(
                        label: 'صافي الربح (ربح - مشتريات)',
                        value: (_result!['totalProfit']! - _buyingTotal!)
                            .toStringAsFixed(2),
                        unit: 'ج.م',
                        highlight: true),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// تقرير منتج معين
// ─────────────────────────────────────────────────────────────────────────────

Widget _datePickerTheme(BuildContext context, Widget? child) => Theme(
      data: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(primary: Colors.orange),
      ),
      child: child!,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DateRangeSelector extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _DateRangeSelector({
    required this.startDate,
    required this.endDate,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DateButton(
            label: 'من',
            date: startDate,
            onTap: onPickStart,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _DateButton(
            label: 'إلى',
            date: endDate,
            onTap: onPickEnd,
          ),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateButton(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.orange.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16.sp, color: Colors.orange),
            SizedBox(width: 6.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.black.withOpacity(0.5))),
                Text(
                  date != null
                      ? '${date!.day}/${date!.month}/${date!.year}'
                      : 'اختر تاريخ',
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black.withOpacity(0.75)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;

  const _SummaryCard(
      {required this.title, required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(14.r),
        ),
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5.w,
                  height: 18.h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(width: 8.w),
                Text(title,
                    style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withOpacity(0.8))),
              ],
            ),
            Divider(height: 16.h, color: Colors.grey.withOpacity(0.3)),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool highlight;
  final bool isDebt;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.unit,
    this.highlight = false,
    this.isDebt = false,
  });

  @override
  Widget build(BuildContext context) {
    Color valueColor = Colors.black.withOpacity(0.8);
    if (highlight) valueColor = Colors.green.shade700;
    if (isDebt) valueColor = Colors.red.shade600;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13.sp, color: Colors.black.withOpacity(0.6))),
          Row(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: valueColor)),
              SizedBox(width: 4.w),
              Text(unit,
                  style: TextStyle(
                      fontSize: 12.sp, color: Colors.black.withOpacity(0.5))),
            ],
          ),
        ],
      ),
    );
  }
}
