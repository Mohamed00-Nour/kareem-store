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
    final confirm = confirmBeforePop ?? () async => true;
    if (await confirm() && context.mounted) {
      Navigator.pop(context);
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
        SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!Navigator.canPop(context)) return null;
              final confirm = confirmBeforePop ?? () async => true;
              confirm().then((ok) {
                if (ok && context.mounted) Navigator.pop(context);
              });
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
