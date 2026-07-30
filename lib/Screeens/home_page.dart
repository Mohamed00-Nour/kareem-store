import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../Widgets/main-cards.dart';
import '../Widgets/app_responsive.dart';
import '../box/MainBoxScreen.dart';
import '../clients/ClientsPage.dart';
import '../departments/DepartmentsPage.dart';
import '../suppliers/SuppliersPage.dart';
import '../reports/ReportsPage.dart';
import 'AddProductPage.dart';
import 'DecreaseProductPage.dart';
import 'QuoteListPage.dart';
import 'ReturnProductPage.dart';
import 'Data/DataEntryScreen.dart';
import 'PrinterSettingsPage.dart';
import 'Invoices/SpecialInvoicesPage.dart';
import '../expenses/ExpensesPage.dart';
import 'ChangeCredentialsPage.dart';
import '../sync/ui/sync_status_badge.dart';

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
    final scaffold = Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        centerTitle: false,
        actions: [
          const SyncStatusBadge(),
          IconButton(
            icon: const Icon(Icons.manage_accounts, color: Colors.white),
            tooltip: 'تغيير بيانات الحساب',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ChangeCredentialsPage()),
              );
            },
          ),
        ],
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
            ResponsiveMenuGrid(
              children: [
                CardWidget(
                  imagePath: 'assets/images/money-growth_18102510.png',
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
                        builder: (context) => const AddProductPage()));
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
                CardWidget(
                  imagePath: 'assets/images/boxes.png',
                  text: 'المنتجات',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const DataEntryScreen()));
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
                  imagePath: 'assets/images/shopping-store_5542724.png',
                  text: 'الاقسام',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => DepartmentsPage()));
                  },
                ),
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
                        builder: (context) => const PrinterSettingsPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/minus.png',
                  text: 'فواتير المرتجع',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ReturnProductPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/expense.png',
                  text: 'المصروفات',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ExpensesPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/request.png',
                  text: 'فواتير مميزة',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const SpecialInvoicesPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/checklist.png',
                  text: 'عرض سعر',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const QuoteListPage()));
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
