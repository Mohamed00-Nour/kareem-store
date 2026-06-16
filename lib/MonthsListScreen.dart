import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../Services/FirebaseService.dart';
import '../Widgets/app_responsive.dart';
import 'PreviousMonthSummaryScreen.dart';

class MonthsListScreen extends StatelessWidget {
  final FirebaseService firebaseService = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الشهور المتاحة'),
      ),
      body: FutureBuilder<List<DateTime>>(
        future: firebaseService.getDistinctMonths(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          } else {
            final months = snapshot.data!;
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: AppResponsive.gridColumns(context),
                crossAxisSpacing: 10.w,
                mainAxisSpacing: 10.h,
                childAspectRatio: 2,
              ),
              padding: EdgeInsets.all(10.w),
              itemCount: months.length,
              itemBuilder: (context, index) {
                final month = months[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PreviousMonthSummaryScreen(
                          startOfMonth: month,
                          endOfMonth: DateTime(month.year, month.month + 1, 1).subtract(Duration(seconds: 1)),
                        ),
                      ),
                    );
                  },
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.0.r),
                    ),
                    elevation: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15.r),
                        color: Colors.orange.withOpacity(0.7),
                      ),
                      child: Center(
                        child: Text(
                          '${month.month}/${month.year}',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}