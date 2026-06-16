import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import '../Buing Invoices/BuyingInvoiceListPage.dart';
import '../Widgets/app_responsive.dart';
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

  late final List<Widget> _pages = [
    const HomePage(handleBackButton: false),
    InvoiceListPage(),
    BuyingInvoiceListPage(),
    ProductListPage(),
  ];

  static const _tabLabels = ['الرئيسية', 'المبيعات', 'المشتريات', 'المنتجات'];
  static const _tabIcons = [
    FontAwesomeIcons.house,
    FontAwesomeIcons.moneyCheckDollar,
    FontAwesomeIcons.boxesStacked,
    FontAwesomeIcons.boxOpen,
  ];

  Future<void> _onBackPressed() async {
    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    final exit = await HomePage.confirmExit(context);
    if (exit && mounted) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: _pages,
    );
  }

  Widget _buildDesktopNav() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      labelType: NavigationRailLabelType.all,
      backgroundColor: Colors.black.withOpacity(0.85),
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: Colors.white.withOpacity(0.55)),
      selectedLabelTextStyle: const TextStyle(color: Colors.white),
      unselectedLabelTextStyle:
          TextStyle(color: Colors.white.withOpacity(0.55)),
      indicatorColor: Colors.orange.withOpacity(0.85),
      destinations: List.generate(
        _tabLabels.length,
        (i) => NavigationRailDestination(
          icon: FaIcon(_tabIcons[i], size: 22),
          selectedIcon: FaIcon(_tabIcons[i], size: 24),
          label: Text(_tabLabels[i]),
        ),
      ),
    );
  }

  Widget _buildMobileNav() {
    return Container(
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
            tabs: List.generate(
              _tabLabels.length,
              (i) => GButton(
                icon: _tabIcons[i],
                text: _tabLabels[i],
                iconSize: 20.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = AppResponsive.isDesktopLayout(context);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _onBackPressed();
        },
        child: Scaffold(
          backgroundColor: const Color(0xffeeeced),
          body: desktop
              ? Row(
                  children: [
                    _buildDesktopNav(),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: _buildBody()),
                  ],
                )
              : _buildBody(),
          bottomNavigationBar: desktop ? null : _buildMobileNav(),
        ),
      ),
    );
  }
}
