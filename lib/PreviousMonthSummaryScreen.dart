import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../Services/FirebaseService.dart';

class PreviousMonthSummaryScreen extends StatelessWidget {
  final DateTime startOfMonth;
  final DateTime endOfMonth;
  final FirebaseService firebaseService = FirebaseService();

  PreviousMonthSummaryScreen({required this.startOfMonth, required this.endOfMonth});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ملخص ${startOfMonth.month}/${startOfMonth.year}'),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0.r),
              ),
              elevation: 3,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.r),
                  color: Colors.orange.withOpacity(0.7),
                ),
                width: double.infinity,
                height: 160.h,
                child: Column(
                  children: [
                    SizedBox(height: 3.h),
                    Center(
                      child: Text(
                        'ملخص ${startOfMonth.month}/${startOfMonth.year}',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    StreamBuilder<Map<String, double>>(
                      stream: firebaseService.getMonthlyProfitAndSumStreamForDateRange(startOfMonth, endOfMonth),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(
                            child: SizedBox(
                              width: 20.w,
                              height: 20.h,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.w,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ),
                          );
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        } else {
                          final data = snapshot.data!;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 10.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إجمالي الربح',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        color: Colors.black.withOpacity(0.7),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${data['totalProfitMargin']!.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                        SizedBox(width: 5.w),
                                        Text(
                                          'L.E',
                                          style: TextStyle(
                                            fontWeight: FontWeight.normal,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 10.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إجمالي المبيعات',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        color: Colors.black.withOpacity(0.7),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${data['totalSum']!.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                        SizedBox(width: 5.w),
                                        Text(
                                          'L.E',
                                          style: TextStyle(
                                            fontWeight: FontWeight.normal,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    StreamBuilder<double>(
                      stream: firebaseService.getMonthlyBuyingInvoicesSumStreamForDateRange(startOfMonth, endOfMonth),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(
                            child: SizedBox(
                              width: 20.w,
                              height: 20.h,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.w,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ),
                          );
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        } else {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 10.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إجمالي المشتريات',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        color: Colors.black.withOpacity(0.7),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${snapshot.data!.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                        SizedBox(width: 5.w),
                                        Text(
                                          'L.E',
                                          style: TextStyle(
                                            fontWeight: FontWeight.normal,
                                            fontSize: 15.sp,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      },
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