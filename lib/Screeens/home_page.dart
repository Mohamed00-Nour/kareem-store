import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../MonthsListScreen.dart';
import '../Services/FirebaseService.dart';
import '../Widgets/main-cards.dart';
import '../box/BoxChangesScreen.dart';
import '../box/MainBoxScreen.dart';
import '../clients/ClientsPage.dart';
import '../departments/DepartmentsPage.dart';
import '../suppliers/SuppliersPage.dart';
import '../reports/ReportsPage.dart';
import 'AddProductPage.dart';
import 'DecreaseProductPage.dart';
import 'ReturnProductPage.dart';
import 'Data/DataEntryScreen.dart';
import 'PrinterSettingsPage.dart';
import 'Invoices/SpecialInvoicesPage.dart';
import '../expenses/ExpensesPage.dart';

class HomePage extends StatelessWidget {
  /// When false, back is handled by [GNavPage] (return to home tab, then exit).
  final bool handleBackButton;

  const HomePage({super.key, this.handleBackButton = true});

  static Future<bool> confirmExit(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xffead1ac),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0.r),
            ),
            title: Text(
              'الخروج من التطبيق',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black.withOpacity(0.7),
                fontWeight: FontWeight.bold,
                fontSize: 20.sp,
              ),
            ),
            content: Text(
              'هل تريد حقا الخروج من التطبيق ؟',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black.withOpacity(0.7),
                fontSize: 18.sp,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'لا',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'نعم',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Confirms leaving a pushed screen (sales, purchases, etc.).
  static Future<bool> confirmNavigateBack(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xffead1ac),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0.r),
            ),
            title: Text(
              'الرجوع',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black.withOpacity(0.7),
                fontWeight: FontWeight.bold,
                fontSize: 20.sp,
              ),
            ),
            content: Text(
              'هل تريد حقا الرجوع؟ قد تفقد التغييرات غير المحفوظة.',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black.withOpacity(0.7),
                fontSize: 18.sp,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'لا',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'نعم',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseService firebaseService = FirebaseService();

    final scaffold = Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          centerTitle: false,
          title: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Image.asset(
                  'assets/Magdy store.png',
                  height: 40.h,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'أبو مجدي للحدايد والعدد',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        backgroundColor: const Color(0xffeeeced),
        body: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 0.0001.sh),
              /*Card(
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
                          'الملخص الشهري',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      StreamBuilder<Map<String, double>>(
                        stream:
                            firebaseService.getMonthlyProfitAndSumStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 10.w),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إجمالي الربح',
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          color:
                                              Colors.black.withOpacity(0.7),
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
                                  padding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 10.w),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إجمالي المبيعات',
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          color:
                                              Colors.black.withOpacity(0.7),
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
                        stream: firebaseService
                            .getMonthlyBuyingInvoicesSumStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 10.w),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إجمالي المشتريات',
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          color:
                                              Colors.black.withOpacity(0.7),
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
              ),*/
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 0.w),
                child: Column(
                  children: [
                    Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 5.h, horizontal: 5.w),
                      child: Row(
                        children: [
                          CardWidget(
                            imagePath:
                                'assets/images/money-growth_18102510.png',
                            text: 'المبيعات',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => DecreaseProductPage()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/boxes_11365317.png',
                            text: 'المشتريات',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const AddProductPage()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/leadership_11802984.png',
                            text: 'العملاء',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => const ClientsPage()));
                            },
                          ),
                          // CardWidget(
                          //   imagePath: 'assets/images/accounting.png',
                          //   text: 'الحسابات',
                          //   onPressed: () {
                          //     Navigator.of(context).push(MaterialPageRoute(
                          //         builder: (context) => const Accounts()));
                          //   },
                          // ),

                          // CardWidget(
                          //   imagePath: 'assets/images/bending.png',
                          //   text: 'الحقن',
                          //   onPressed: () {
                          //     Navigator.of(context).push(MaterialPageRoute(
                          //         builder: (context) =>
                          //             const InjectedProductPage()));
                          //   },
                          // ),
                        ],
                      ),
                    ),
                    Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 5.h, horizontal: 5.w),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          CardWidget(
                            imagePath: 'assets/images/boxes.png',
                            text: 'المنتجات',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const DataEntryScreen()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/supplier_12112173.png',
                            text: 'الموردين',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => const SuppliersPage()));
                            },
                          ),
                          CardWidget(
                            imagePath:
                                'assets/images/shopping-store_5542724.png',
                            text: 'الاقسام',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => DepartmentsPage()));
                            },
                          ),
                          // CardWidget(
                          //   imagePath: 'assets/images/pipe.png',
                          //   text: 'السحب',
                          //   onPressed: () {
                          //     Navigator.of(context).push(MaterialPageRoute(
                          //         builder: (context) => PipesPage()));
                          //   },
                          // ),
                          // CardWidget(
                          //   imagePath: 'assets/images/checklist.png',
                          //   text: 'الحضور',
                          //   onPressed: () {
                          //     Navigator.of(context).push(MaterialPageRoute(
                          //         builder: (context) =>
                          //             const AttendanceWidget()));
                          //   },
                          // ),
                          // CardWidget(
                          //   imagePath: 'assets/images/division.png',
                          //   text: 'الموظفين',
                          //   onPressed: () {
                          //     Navigator.of(context).push(MaterialPageRoute(
                          //         builder: (context) => EmployeeList()));
                          //   },
                          // ),
                        ],
                      ),
                    ),
                    Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 5.h, horizontal: 5.w),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          CardWidget(
                            imagePath: 'assets/images/money-bag.png',
                            text: 'صندوق المالية',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => const MainBoxScreen()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/data-analytics.png',
                            text: 'الإستعلامات',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => const ReportsPage()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/appliance.png',
                            text: 'الطابعة',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const PrinterSettingsPage()));
                            },
                          ),
                          
                        ],
                     
                     
                     ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
              CardWidget(
    
                            imagePath: 'assets/images/minus.png',
                            text: 'فواتير المرتجع',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const ReturnProductPage()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/expense.png',
                            text: 'المصروفات',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const ExpensesPage()));
                            },
                          ),
                          CardWidget(
                            imagePath: 'assets/images/request.png',
                            text: 'فواتير مميزة',
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) =>
                                      const SpecialInvoicesPage()));
                            },
                          ),
            ],
          ),
          ],
        ),
      ),
    );

    if (!handleBackButton) return scaffold;

    return WillPopScope(
      onWillPop: () => confirmExit(context),
      child: scaffold,
    );
  }
}
