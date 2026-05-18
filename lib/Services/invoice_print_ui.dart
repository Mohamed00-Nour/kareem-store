import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/printer_settings.dart';
import 'invoice_print_service.dart';
import 'printer_settings_service.dart';

/// Shows loading while printing and snackbars for success/failure.
class InvoicePrintUi {
  /// Temporary: shows thermal receipt text before printing (remove when done testing).
  static Future<void> previewInvoice(
    BuildContext context,
    Map<String, dynamic> invoice, {
    String? clientId,
  }) async {
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
                  'جاري تحضير المعاينة...',
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

    String previewText;
    try {
      previewText = await InvoicePrintService.buildPrintPreviewText(
        invoice,
        clientId: clientId,
      );
    } catch (e) {
      previewText = 'تعذر تحضير المعاينة:\n$e';
    }

    final loadingCtx = loadingDialogContext;
    if (loadingCtx != null && loadingCtx.mounted) {
      Navigator.of(loadingCtx).pop();
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xfff5f0e6),
          title: Text(
            'معاينة الطباعة (مؤقت)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18.sp,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'هذا شكل الإيصال على الطابعة الحرارية تقريباً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                ),
                SizedBox(height: 10.h),
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(maxHeight: 420.h),
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      previewText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.sp,
                        height: 1.35,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: previewText));
                Navigator.pop(ctx);
                _snack(context, 'تم نسخ المعاينة');
              },
              child: Text('نسخ', style: TextStyle(fontSize: 14.sp)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إغلاق', style: TextStyle(fontSize: 14.sp)),
            ),
          ],
        ),
      ),
    );
  }

  /// Temporary icon button — remove with [previewInvoice] when testing is done.
  static Widget temporaryPreviewIconButton(
    BuildContext context,
    Map<String, dynamic> invoice, {
    String? clientId,
    double iconSize = 20,
  }) {
    return IconButton(
      icon: Icon(Icons.receipt_long, size: iconSize, color: Colors.deepPurple),
      tooltip: 'معاينة الطباعة (مؤقت)',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
      onPressed: () => previewInvoice(context, invoice, clientId: clientId),
    );
  }

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
