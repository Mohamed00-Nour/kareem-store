import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Screeens/home_page.dart';

/// App bar leading: back when this route was pushed, else optional drawer/menu.
class AppBarNavLeading extends StatelessWidget {
  final VoidCallback? openDrawer;
  final Future<bool> Function()? confirmBeforePop;

  const AppBarNavLeading({
    super.key,
    this.openDrawer,
    this.confirmBeforePop,
  });

  Future<void> _handleBack(BuildContext context) async {
    if (confirmBeforePop != null) {
      final confirm = confirmBeforePop!;
      if (await confirm() && context.mounted) {
        Navigator.pop(context);
      }
    } else {
      if (context.mounted) {
        await Navigator.maybePop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Navigator.canPop(context)) {
      return IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: 'رجوع',
        onPressed: () => _handleBack(context),
      );
    }
    if (openDrawer != null) {
      return IconButton(
        icon: const Icon(Icons.menu, color: Colors.white),
        tooltip: 'القائمة',
        onPressed: openDrawer,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Private intent used exclusively for desktop back-navigation shortcuts.
/// Using a custom intent avoids conflicts with Flutter's built-in [ActivateIntent]
/// which is consumed by buttons, checkboxes, and other interactive widgets.
class _BackNavigationIntent extends Intent {
  const _BackNavigationIntent();
}

/// Wraps a screen so Escape / Alt+Left triggers the same back flow on desktop.
class DesktopBackShortcuts extends StatelessWidget {
  final Widget child;
  final Future<bool> Function()? confirmBeforePop;

  const DesktopBackShortcuts({
    super.key,
    required this.child,
    this.confirmBeforePop,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _BackNavigationIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _BackNavigationIntent(),
      },
      child: Actions(
        actions: {
          _BackNavigationIntent:
              CallbackAction<_BackNavigationIntent>(
            onInvoke: (_) {
              if (!Navigator.canPop(context)) return null;
              if (confirmBeforePop != null) {
                confirmBeforePop!().then((ok) {
                  if (ok && context.mounted) Navigator.pop(context);
                });
              } else {
                if (context.mounted) {
                  Navigator.maybePop(context);
                }
              }
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Shared confirm-before-leave used by sales / purchase invoice screens.
Future<bool> confirmLeaveInvoiceScreen(BuildContext context) =>
    HomePage.confirmNavigateBack(context);
