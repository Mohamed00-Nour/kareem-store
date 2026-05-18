import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import '../Buing Invoices/BuyingInvoiceListPage.dart';
import 'Invoices/All_invoices.dart';
import 'ProductListPage.dart';
import 'home_page.dart';

class GNavPage extends StatefulWidget {
  const GNavPage({super.key});

  @override
  State<GNavPage> createState() => _GNavPageState();
}

class _GNavPageState extends State<GNavPage> {
  int _selectedIndex = 0;

  static final _pages = <Widget>[
    const HomePage(),
    InvoiceListPage(),
    BuyingInvoiceListPage(),
    ProductListPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: PopScope(
        canPop: _selectedIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xffeeeced),
          body: IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),
          bottomNavigationBar: Container(
            margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.r),
              color: Colors.black.withOpacity(0.75),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
                child: GNav(
                  gap: 6.w,
                  haptic: false,
                  tabBorderRadius: 12.r,
                  curve: Curves.easeOutCubic,
                  duration: const Duration(milliseconds: 250),
                  color: Colors.white.withOpacity(0.55),
                  activeColor: Colors.white,
                  tabBackgroundColor: Colors.orange.withOpacity(0.85),
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
                  selectedIndex: _selectedIndex,
                  onTabChange: (index) => setState(() => _selectedIndex = index),
                  tabs: [
                    GButton(
                      icon: FontAwesomeIcons.house,
                      text: 'الرئيسية',
                      iconSize: 20.sp,
                    ),
                    GButton(
                      icon: FontAwesomeIcons.moneyCheckDollar,
                      text: 'المبيعات',
                      iconSize: 20.sp,
                    ),
                    GButton(
                      icon: FontAwesomeIcons.boxesStacked,
                      text: 'المشتريات',
                      iconSize: 20.sp,
                    ),
                    GButton(
                      icon: FontAwesomeIcons.boxOpen,
                      text: 'المنتجات',
                      iconSize: 20.sp,
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
