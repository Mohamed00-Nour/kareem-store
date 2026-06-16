import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app_responsive.dart';

/// Single app-wide ScreenUtil setup.
///
/// Uses the current window size as [designSize] so `.w`, `.h`, and `.sp` map to
/// logical pixels (scale ≈ 1). Avoids the old multi-breakpoint scaling that made
/// some screens huge or crash on resize.
class ResponsiveScreenUtilHost extends StatefulWidget {
  final Widget Function(BuildContext context) builder;

  const ResponsiveScreenUtilHost({super.key, required this.builder});

  @override
  State<ResponsiveScreenUtilHost> createState() =>
      _ResponsiveScreenUtilHostState();
}

class _ResponsiveScreenUtilHostState extends State<ResponsiveScreenUtilHost>
    with WidgetsBindingObserver {
  Size _designSize = AppResponsive.screenUtilDesignSize();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDesignSize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _syncDesignSize();
  }

  void _syncDesignSize() {
    if (!mounted) return;
    final next = AppResponsive.screenUtilDesignSize();
    final sameWidth = next.width.round() == _designSize.width.round();
    final sameHeight = next.height.round() == _designSize.height.round();
    if (sameWidth && sameHeight) return;
    setState(() => _designSize = next);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: _designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) => widget.builder(context),
    );
  }
}
