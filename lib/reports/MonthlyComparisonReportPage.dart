import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MonthlyComparisonReportPage extends StatefulWidget {
  const MonthlyComparisonReportPage({super.key});

  @override
  State<MonthlyComparisonReportPage> createState() =>
      _MonthlyComparisonReportPageState();
}

class _MonthlyComparisonReportPageState
    extends State<MonthlyComparisonReportPage> {
  bool _loading = true;
  List<_MonthStat> _months = [];

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() => _loading = true);
    try {
      final invoicesSnap =
          await FirebaseFirestore.instance.collection('invoices').get();
      final buyingSnap = await FirebaseFirestore.instance
          .collection('buying invoices')
          .get();

      final Map<String, _MonthStat> statsMap = {};

      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        Timestamp? ts;
        if (data['date'] is Timestamp) {
          ts = data['date'] as Timestamp;
        }
        if (ts == null) continue;
        final date = ts.toDate();
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';

        final totalSum = (data['totalSum'] ?? 0.0).toDouble();
        final profit = (data['profitMargin'] ?? 0.0).toDouble();

        if (statsMap.containsKey(key)) {
          statsMap[key] = _MonthStat(
            year: date.year,
            month: date.month,
            totalSales: statsMap[key]!.totalSales + totalSum,
            totalProfit: statsMap[key]!.totalProfit + profit,
            totalBuying: statsMap[key]!.totalBuying,
            invoiceCount: statsMap[key]!.invoiceCount + 1,
          );
        } else {
          statsMap[key] = _MonthStat(
            year: date.year,
            month: date.month,
            totalSales: totalSum,
            totalProfit: profit,
            totalBuying: 0,
            invoiceCount: 1,
          );
        }
      }

      for (final doc in buyingSnap.docs) {
        final data = doc.data();
        Timestamp? ts;
        if (data['date'] is Timestamp) {
          ts = data['date'] as Timestamp;
        }
        if (ts == null) continue;
        final date = ts.toDate();
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final totalSum = (data['totalSum'] ?? 0.0).toDouble();

        if (statsMap.containsKey(key)) {
          statsMap[key] = _MonthStat(
            year: date.year,
            month: date.month,
            totalSales: statsMap[key]!.totalSales,
            totalProfit: statsMap[key]!.totalProfit,
            totalBuying: statsMap[key]!.totalBuying + totalSum,
            invoiceCount: statsMap[key]!.invoiceCount,
          );
        } else {
          statsMap[key] = _MonthStat(
            year: date.year,
            month: date.month,
            totalSales: 0,
            totalProfit: 0,
            totalBuying: totalSum,
            invoiceCount: 0,
          );
        }
      }

      final sorted = statsMap.values.toList()
        ..sort((a, b) {
          final aDate = DateTime(a.year, a.month);
          final bDate = DateTime(b.year, b.month);
          return bDate.compareTo(aDate);
        });

      setState(() {
        _months = sorted;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  static const List<String> _arabicMonths = [
    '',
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'المقارنة الشهرية',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _months.isEmpty
                ? Center(
                    child: Text('لا توجد بيانات',
                        style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.black.withOpacity(0.5))),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(12.w),
                    itemCount: _months.length,
                    itemBuilder: (ctx, i) {
                      final m = _months[i];
                      final monthName = _arabicMonths[m.month];
                      return Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r)),
                        margin: EdgeInsets.symmetric(vertical: 6.h),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          padding: EdgeInsets.all(14.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Month header
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 4.h),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.orange.withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(8.r),
                                    ),
                                    child: Text(
                                      '$monthName ${m.year}',
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${m.invoiceCount} فاتورة',
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color:
                                            Colors.black.withOpacity(0.5)),
                                  ),
                                ],
                              ),
                              Divider(
                                  height: 14.h,
                                  color: Colors.grey.withOpacity(0.3)),
                              _MonthRow(
                                label: 'إجمالي المبيعات',
                                value:
                                    '${m.totalSales.toStringAsFixed(2)} ج.م',
                                color: Colors.blue,
                              ),
                              _MonthRow(
                                label: 'إجمالي المشتريات',
                                value:
                                    '${m.totalBuying.toStringAsFixed(2)} ج.م',
                                color: Colors.purple,
                              ),
                              _MonthRow(
                                label: 'إجمالي الأرباح',
                                value:
                                    '${m.totalProfit.toStringAsFixed(2)} ج.م',
                                color: Colors.green,
                              ),
                              _MonthRow(
                                label: 'صافي الربح (ربح - مشتريات)',
                                value:
                                    '${(m.totalProfit - m.totalBuying).toStringAsFixed(2)} ج.م',
                                color: (m.totalProfit - m.totalBuying) >= 0
                                    ? Colors.teal
                                    : Colors.red,
                                isBold: true,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _MonthStat {
  final int year;
  final int month;
  final double totalSales;
  final double totalProfit;
  final double totalBuying;
  final int invoiceCount;

  const _MonthStat({
    required this.year,
    required this.month,
    required this.totalSales,
    required this.totalProfit,
    required this.totalBuying,
    required this.invoiceCount,
  });
}

class _MonthRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _MonthRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.black.withOpacity(0.6))),
          Text(value,
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
