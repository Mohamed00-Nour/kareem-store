import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/printer_settings.dart';
import 'invoice_print_service.dart';
import 'printer_settings_service.dart';

/// Shows loading while printing and snackbars for success/failure.
class InvoicePrintUi {
  static Future<void> printInvoice(
    BuildContext context,
    Map<String, dynamic> invoice, {
    String? clientId,
  }) async {
    if (!context.mounted) return;

    final settings = await PrinterSettingsService.load();
    if (settings.connectionType != PrinterConnectionType.bluetooth) {
      _snack(
        context,
        'يرجى اختيار طابعة Bluetooth من إعدادات الطابعة',
      );
      return;
    }
    if (settings.bluetoothMacAddress.trim().isEmpty) {
      _snack(
        context,
        'يرجى ربط الطابعة من إعدادات الطابعة أولاً (أدخل MAC أو بحث)',
      );
      return;
    }

    if (!context.mounted) return;
    BuildContext? loadingDialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        loadingDialogContext = dialogCtx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xffead1ac),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.orange),
                SizedBox(height: 16.h),
                Text(
                  'جاري طباعة الفاتورة...',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );

    final result = await InvoicePrintService.printSalesInvoice(
      invoice,
      clientId: clientId,
    );

    final loadingCtx = loadingDialogContext;
    if (loadingCtx != null && loadingCtx.mounted) {
      Navigator.of(loadingCtx).pop();
    }
    if (!context.mounted) return;

    _snack(
      context,
      result.success
          ? 'تمت طباعة الفاتورة بنجاح'
          : (result.messageAr.isNotEmpty
              ? result.messageAr
              : 'فشلت طباعة الفاتورة'),
      seconds: result.success ? 3 : 8,
    );
  }

  static void _snack(
    BuildContext context,
    String text, {
    int seconds = 4,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: seconds),
        content: Text(text),
      ),
    );
  }
}
