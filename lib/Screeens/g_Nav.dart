import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../Buing Invoices/BuyingInvoiceListPage.dart';
import 'All_Borrow.dart';
import 'Materials/MaterialTrackingPage.dart';
import 'ProductAndPipePage.dart';
import 'ProductListPage.dart';
import 'home_page.dart';
import 'Invoices/All_invoices.dart';

class GNavPage extends StatefulWidget {
  @override
  State<GNavPage> createState() => _GNavPageState();
}

class _GNavPageState extends State<GNavPage> {
  int _selectedIndex = 0;
  static const TextStyle optionStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    final List<Widget> _widgetOptions = <Widget>[
      HomePage(),
      InvoiceListPage(),
      BuyingInvoiceListPage(),
      ProductListPage(),
    ];

    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Color(0xffeeeced),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.symmetric(vertical: 15.h, horizontal: 10.w),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.r),
              color: Colors.black.withOpacity(0.7),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(8.0.w),
                child: GNav(
                  duration: const Duration(milliseconds: 200),
                  textStyle: optionStyle.copyWith(fontSize: 10.sp),
                  color: Colors.black.withOpacity(0.7),
                  haptic: false,
                  selectedIndex: _selectedIndex,
                  onTabChange: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  tabs: [
                    GButton(
                      borderRadius: BorderRadius.circular(10.r),
                      iconActiveColor: Colors.white.withOpacity(0.7),
                      textColor: Colors.black.withOpacity(0.7),
                      backgroundColor: Colors.orange.withOpacity(0.8),
                      gap: 6.w,
                      iconColor: Colors.white.withOpacity(0.7),
                      iconSize: 16.sp,
                      icon: FontAwesomeIcons.house,
                      text: 'الرئيسية',
                    ),
                    GButton(
                      borderRadius: BorderRadius.circular(10.r),
                      iconActiveColor: Colors.white.withOpacity(0.7),
                      textColor: Colors.black.withOpacity(0.7),
                      backgroundColor: Colors.orange.withOpacity(0.7),
                      gap: 6.w,
                      iconColor: Colors.white.withOpacity(0.7),
                      iconSize: 16.sp,
                      icon: FontAwesomeIcons.moneyCheckDollar,
                      text: 'المبيعات',
                    ),
                    GButton(
                      borderRadius: BorderRadius.circular(10.r),
                      iconActiveColor: Colors.white.withOpacity(0.7),
                      textColor: Colors.black.withOpacity(0.7),
                      backgroundColor: Colors.orange.withOpacity(0.7),
                      gap: 6.w,
                      iconColor: Colors.white.withOpacity(0.7),
                      iconSize: 16.sp,
                      icon: FontAwesomeIcons.boxesStacked,
                      text: 'المشتريات',
                    ),
                    GButton(
                      borderRadius: BorderRadius.circular(10.r),
                      iconActiveColor: Colors.white.withOpacity(0.7),
                      textColor: Colors.black.withOpacity(0.7),
                      backgroundColor: Colors.orange.withOpacity(0.7),
                      gap: 6.w,
                      iconColor: Colors.white.withOpacity(0.7),
                      iconSize: 16.sp,
                      icon: FontAwesomeIcons.boxOpen,
                      text: 'المنتجات',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
