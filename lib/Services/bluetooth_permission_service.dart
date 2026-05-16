import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'thermal_print_channel.dart';

/// Requests Bluetooth access on app start so thermal printers can connect.
class BluetoothPermissionService {
  BluetoothPermissionService._();

  static Future<bool> hasPrinterBluetoothAccess() async {
    if (!Platform.isAndroid) return true;

    if (await ThermalPrintChannel.isPermissionBluetoothGranted()) {
      return true;
    }

    final connect = await Permission.bluetoothConnect.status;
    if (connect.isGranted) return true;

    final scan = await Permission.bluetoothScan.status;
    if (scan.isGranted) return true;

    // Android 11 and below: some devices need location to list paired printers.
    final location = await Permission.locationWhenInUse.status;
    if (location.isGranted) return true;

    return false;
  }

  static Future<bool> requestPrinterBluetoothAccess() async {
    if (!Platform.isAndroid) return true;

    var connect = await Permission.bluetoothConnect.request();
    if (connect.isGranted) return true;

    var scan = await Permission.bluetoothScan.request();
    if (scan.isGranted) return true;

    if (await ThermalPrintChannel.isPermissionBluetoothGranted()) {
      return true;
    }

    // Older Android / some OEMs when reading paired devices.
    final location = await Permission.locationWhenInUse.request();
    if (location.isGranted) return true;

    connect = await Permission.bluetoothConnect.status;
    scan = await Permission.bluetoothScan.status;
    return connect.isGranted ||
        scan.isGranted ||
        await ThermalPrintChannel.isPermissionBluetoothGranted();
  }

  /// Called on splash: explains why, then shows system permission dialog.
  static Future<void> ensureOnAppStart(BuildContext context) async {
    if (!Platform.isAndroid) return;

    if (await hasPrinterBluetoothAccess()) return;
    if (!context.mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'صلاحية البلوتوث للطابعة',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'يحتاج التطبيق صلاحية البلوتوث للاتصال بطابعة الإيصالات الحرارية '
            '(مثل الطابعة المحمولة 58mm / 80mm) وطباعة فواتير المبيعات.\n\n'
            'يرجى الضغط على «موافق» ثم اختيار «السماح» في الشاشة التالية.\n'
            'إذا ظهرت «الأجهزة القريبة» أو Nearby devices فعّلها أيضاً.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقاً'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );

    if (shouldRequest != true || !context.mounted) return;

    final granted = await requestPrinterBluetoothAccess();
    if (granted || !context.mounted) return;

    final permanentlyDenied = await _isPermanentlyDenied();
    if (!permanentlyDenied || !context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'صلاحية البلوتوث مطلوبة',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'تم رفض صلاحية البلوتوث. لتتمكن من ربط الطابعة، افتح إعدادات التطبيق '
            'وفعّل «الأجهزة القريبة» / Bluetooth.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> _isPermanentlyDenied() async {
    final connect = await Permission.bluetoothConnect.status;
    final scan = await Permission.bluetoothScan.status;
    return connect.isPermanentlyDenied ||
        scan.isPermanentlyDenied ||
        connect.isRestricted ||
        scan.isRestricted;
  }
}
