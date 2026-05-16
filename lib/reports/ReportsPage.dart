import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'SalesReportPage.dart';
import 'ProductReportPage.dart';
import 'BestProductsReportPage.dart';
import 'ClientsReportPage.dart';
import 'InventoryReportPage.dart';
import 'MonthlyComparisonReportPage.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<_ReportCard> cards = [
      _ReportCard(
        title: 'تقرير المبيعات',
        subtitle: 'المبيعات والأرباح لفترة زمنية محددة',
        icon: Icons.bar_chart_rounded,
        color: Colors.orange,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SalesReportPage())),
      ),
      _ReportCard(
        title: 'تقرير منتج',
        subtitle: 'أداء منتج معين خلال فترة زمنية',
        icon: Icons.inventory_2_outlined,
        color: Colors.blue,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProductReportPage())),
      ),
      _ReportCard(
        title: 'أفضل المنتجات',
        subtitle: 'المنتجات الأكثر مبيعاً والأعلى ربحاً',
        icon: Icons.emoji_events_outlined,
        color: Colors.amber.shade700,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BestProductsReportPage())),
      ),
      _ReportCard(
        title: 'تقرير العملاء',
        subtitle: 'أفضل العملاء والديون المستحقة',
        icon: Icons.people_outline,
        color: Colors.green,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ClientsReportPage())),
      ),
      _ReportCard(
        title: 'تقرير المخزون',
        subtitle: 'قيمة المخزون والمنتجات المنخفضة',
        icon: Icons.warehouse_outlined,
        color: Colors.purple,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InventoryReportPage())),
      ),
      _ReportCard(
        title: 'المقارنة الشهرية',
        subtitle: 'مقارنة الأرباح والمبيعات شهرياً',
        icon: Icons.compare_arrows_rounded,
        color: Colors.teal,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const MonthlyComparisonReportPage())),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'التقارير',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Padding(
          padding: EdgeInsets.all(12.w),
          child: GridView.builder(
            itemCount: cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12.w,
              mainAxisSpacing: 12.h,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final card = cards[index];
              return GestureDetector(
                onTap: card.onTap,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.r),
                      color: Colors.white.withOpacity(0.85),
                    ),
                    padding: EdgeInsets.all(14.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: card.color.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            card.icon,
                            color: card.color,
                            size: 32.sp,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Text(
                          card.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          card.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReportCard {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
