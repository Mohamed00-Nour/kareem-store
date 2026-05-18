import 'package:flutter/foundation.dart';

import '../models/paired_bluetooth_device.dart';
import 'app_error_logger.dart';
import '../models/printer_settings.dart';
import 'bluetooth_permission_service.dart';
import 'invoice_print_formatter.dart';
import 'thermal_print_channel.dart';

class BluetoothPrinterService {
  static const _escCut = [0x1D, 0x56, 0x00];
  static const _escDrawerKick = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  static Future<bool> ensurePermissions() async {
    if (await BluetoothPermissionService.hasPrinterBluetoothAccess()) {
      return true;
    }
    return BluetoothPermissionService.requestPrinterBluetoothAccess();
  }

  static Future<bool> isBluetoothOn() async {
    return ThermalPrintChannel.bluetoothEnabled();
  }

  static Future<List<PairedBluetoothDevice>> getPairedDevices() async {
    await ensurePermissions();
    return ThermalPrintChannel.pairedDevices();
  }

  static String _normalizeMac(String mac) => mac.trim().toUpperCase();

  static Future<bool> connect(String macAddress) async {
    final mac = _normalizeMac(macAddress);
    if (mac.isEmpty) return false;
    await ensurePermissions();

    // Clear stale socket (common cause of "paired but connect fails").
    try {
      await ThermalPrintChannel.disconnect();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // One connect attempt — multiple native fallbacks run inside Android code.
    try {
      final ok = await ThermalPrintChannel.connect(mac);
      if (!ok) {
        AppErrorLogger.logFailure(
          step: 'bluetooth_printer_connect',
          message: 'Bluetooth connect returned false',
          metadata: {'mac': mac},
        );
      }
      return ok;
    } catch (e, st) {
      debugPrint('Bluetooth connect error: $e\n$st');
      await AppErrorLogger.record(
        error: e,
        stackTrace: st,
        step: 'bluetooth_printer_connect',
        metadata: {'mac': mac},
      );
      return false;
    }
  }

  static Future<bool> isConnected() async {
    return ThermalPrintChannel.connectionStatus();
  }

  static Future<void> disconnect() async {
    await ThermalPrintChannel.disconnect();
  }

  static Future<bool> _ensureConnected(PrinterSettings settings) async {
    if (await isConnected()) return true;
    if (settings.bluetoothMacAddress.isEmpty) return false;
    return connect(settings.bluetoothMacAddress);
  }

  static int _textSizeFromFont(int fontSize) {
    if (fontSize >= 40) return 5;
    if (fontSize >= 35) return 4;
    if (fontSize >= 30) return 3;
    if (fontSize >= 25) return 2;
    return 1;
  }

  static Future<bool> _writeLine(
    String text, {
    int size = 2,
    required ThermalPaperSize paperSize,
  }) async {
    return ThermalPrintChannel.writeString(
      size: size,
      text: text,
      paperSize: paperSize,
    );
  }

  static Future<bool> _writeRaw(List<int> bytes) async {
    return ThermalPrintChannel.writeBytes(bytes);
  }

  static Future<bool> _finishReceipt(PrinterSettings settings) async {
    final trailingLines =
        settings.textHeightPosition + settings.bottomMargin;
    for (var i = 0; i < trailingLines; i++) {
      final ok = await _writeLine('\n', size: 1, paperSize: settings.paperSize);
      if (!ok) return false;
    }
    if (settings.salesInvoiceFooter.isNotEmpty) {
      final ok = await _writeLine(
        settings.salesInvoiceFooter,
        size: _textSizeFromFont(settings.fontSize),
        paperSize: settings.paperSize,
      );
      if (!ok) return false;
    }
    await _writeLine('\n\n', size: 1, paperSize: settings.paperSize);
    if (settings.paperCutCommand > 0) {
      final ok = await _writeRaw(_escCut);
      if (!ok) return false;
    }
    if (settings.drawerOpenCommand > 0) {
      return _writeRaw(_escDrawerKick);
    }
    return true;
  }

  static Future<bool> printTestReceipt(PrinterSettings settings) async {
    if (!await _ensureConnected(settings)) return false;

    final size = _textSizeFromFont(settings.fontSize);
    for (var copy = 0; copy < settings.invoiceCopies; copy++) {
      if (!await ThermalPrintChannel.initPaperLayout(settings.paperSize)) {
        return false;
      }
      if (!await _writeLine('Kareem Store\n',
          size: size, paperSize: settings.paperSize)) {
        return false;
      }
      if (!await _writeLine('اختبار الطابعة\n',
          size: size, paperSize: settings.paperSize)) {
        return false;
      }
      final deviceLabel = settings.bluetoothDeviceName.isNotEmpty
          ? settings.bluetoothDeviceName
          : settings.bluetoothMacAddress;
      if (deviceLabel.isNotEmpty) {
        if (!await _writeLine('$deviceLabel\n',
            size: 1, paperSize: settings.paperSize)) {
          return false;
        }
      }
      if (!await _finishReceipt(settings)) return false;
    }
    return true;
  }

  static Future<bool> printSalesInvoice({
    required Map<String, dynamic> invoice,
    required PrinterSettings settings,
    InvoicePrintContext context = const InvoicePrintContext(),
  }) async {
    if (settings.connectionType != PrinterConnectionType.bluetooth) {
      return false;
    }
    final text = InvoicePrintFormatter.format(
      invoice: invoice,
      settings: settings,
      context: context,
    );
    return printText(text, settings: settings);
  }

  static Future<bool> printText(
    String text, {
    required PrinterSettings settings,
  }) async {
    if (!await _ensureConnected(settings)) return false;

    final size = _textSizeFromFont(settings.fontSize);
    for (var copy = 0; copy < settings.invoiceCopies; copy++) {
      if (!await ThermalPrintChannel.initPaperLayout(settings.paperSize)) {
        return false;
      }
      for (final line in text.split('\n')) {
        final content = line.isEmpty ? '\n' : '$line\n';
        if (!await _writeLine(content,
            size: size, paperSize: settings.paperSize)) {
          return false;
        }
      }
      if (!await _finishReceipt(settings)) return false;
    }
    return true;
  }
}
