import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared breakpoints and layout helpers for phone, tablet, and desktop.
class AppResponsive {
  AppResponsive._();

  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Fallback when the window size is not ready yet.
  static const Size fallbackMobileDesignSize = Size(360, 690);
  static const Size fallbackDesktopDesignSize = Size(1280, 720);

  static bool isDesktopPlatform() {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  /// Current window size — also used as ScreenUtil [designSize] (1:1 logical pixels).
  static Size windowSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return isDesktopPlatform()
          ? fallbackDesktopDesignSize
          : fallbackMobileDesignSize;
    }
    final view = views.first;
    final width = view.physicalSize.width / view.devicePixelRatio;
    final height = view.physicalSize.height / view.devicePixelRatio;
    return Size(
      width.clamp(320, 3840),
      height.clamp(480, 2400),
    );
  }

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isMobile(BuildContext context) =>
      widthOf(context) < mobileBreakpoint;

  static bool isDesktopLayout(BuildContext context) =>
      widthOf(context) >= tabletBreakpoint;

  static bool isWideDesktop(BuildContext context) =>
      widthOf(context) >= desktopBreakpoint;

  static int gridColumns(
    BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
    final w = widthOf(context);
    if (w >= desktopBreakpoint) return desktop;
    if (w >= tabletBreakpoint) return tablet;
    if (w >= mobileBreakpoint) return mobile + 1;
    return mobile;
  }

  static int homeMenuColumns(BuildContext context) {
    final w = widthOf(context);
    if (w >= desktopBreakpoint) return 6;
    if (w >= tabletBreakpoint) return 4;
    return 3;
  }

  static double homeMenuTileSize(BuildContext context) {
    final cols = homeMenuColumns(context);
    final w = widthOf(context);
    const horizontalPad = 16.0;
    const spacing = 8.0;
    return (w - horizontalPad - spacing * (cols - 1)) / cols;
  }

  /// Stable ScreenUtil design size — one scale for the whole app.
  static Size screenUtilDesignSize() {
    final window = windowSize();
    if (isDesktopPlatform() && window.width >= tabletBreakpoint) {
      // ~1.2× UI on desktop — readable, never the old 3×+ scaling.
      return Size(
        (window.width / 1.2).clamp(900, 1600),
        (window.height / 1.2).clamp(600, 1200),
      );
    }
    return window;
  }
}

/// Clamps system text scaling so desktop windows do not blow up fonts.
class ResponsiveAppShell extends StatelessWidget {
  final Widget child;

  const ResponsiveAppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxTextScale = AppResponsive.isDesktopPlatform() ? 1.08 : 1.25;
    return MediaQuery(
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: maxTextScale,
        ),
      ),
      child: child,
    );
  }
}

/// Enables mouse / trackpad scrolling on desktop.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Wraps a grid of home menu tiles with responsive column count.
class ResponsiveMenuGrid extends StatelessWidget {
  final List<Widget> children;

  const ResponsiveMenuGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final tileSize = AppResponsive.homeMenuTileSize(context);
    const spacing = 8.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        alignment: WrapAlignment.start,
        children: children
            .map(
              (child) => SizedBox(
                width: tileSize,
                height: tileSize,
                child: child,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Optional max-width wrapper for very wide form screens.
class ResponsiveContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 1400,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
