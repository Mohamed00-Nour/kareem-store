import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/paired_bluetooth_device.dart';
import '../models/printer_settings.dart';

/// Dart bridge to native Bluetooth thermal printing (custom Android handler
/// with RFCOMM fallback; falls back to [print_bluetooth_thermal] on other platforms).
class ThermalPrintChannel {
  ThermalPrintChannel._();

  static const MethodChannel _channel =
      MethodChannel('kareem.store/thermal_bt');

  static const MethodChannel _legacyChannel =
      MethodChannel('groons.web.app/print');

  static Future<bool> isPermissionBluetoothGranted() async {
    try {
      return await _channel
              .invokeMethod<bool>('ispermissionbluetoothgranted') ??
          false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Bluetooth permission check failed: $e');
      return false;
    }
  }

  static Future<bool> bluetoothEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('bluetoothenabled') ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Bluetooth enabled check failed: $e');
      return false;
    }
  }

  static String _normalizeMac(String mac) => mac.trim().toUpperCase();

  static PairedBluetoothDevice _parsePairedEntry(String item) {
    final hash = item.lastIndexOf('#');
    if (hash <= 0) {
      return PairedBluetoothDevice(name: item, macAddress: '');
    }
    return PairedBluetoothDevice(
      name: item.substring(0, hash),
      macAddress: _normalizeMac(item.substring(hash + 1)),
    );
  }

  static Future<List<PairedBluetoothDevice>> pairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('pairedbluetooths');
      if (result == null) return [];
      return result.map((item) => _parsePairedEntry(item.toString())).toList();
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Paired bluetooth list failed: $e');
      return [];
    }
  }

  static Future<bool> connectionStatus() async {
    try {
      return await _channel.invokeMethod<bool>('connectionstatus') ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Connection status failed: $e');
      return false;
    }
  }

  static Future<bool> connect(String macAddress) async {
    final mac = _normalizeMac(macAddress);
    if (mac.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('connect', mac) ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Bluetooth connect failed: $e');
      return false;
    } on MissingPluginException {
      try {
        return await _legacyChannel.invokeMethod<bool>('connect', mac) ??
            false;
      } on PlatformException catch (e) {
        if (kDebugMode) debugPrint('Legacy bluetooth connect failed: $e');
        return false;
      }
    }
  }

  static Future<bool> disconnect() async {
    try {
      return await _channel.invokeMethod<bool>('disconnect') ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Bluetooth disconnect failed: $e');
      return false;
    }
  }

  static Future<bool> writeBytes(List<int> bytes) async {
    try {
      return await _channel.invokeMethod<bool>('writebytes', bytes) ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Write bytes failed: $e');
      return false;
    }
  }

  static Future<bool> writeString({
    required int size,
    required String text,
    ThermalPaperSize paperSize = ThermalPaperSize.mm80,
  }) async {
    final clampedSize = size.clamp(1, 5);
    final paperMm = paperSize.widthMm;
    try {
      return await _channel.invokeMethod<bool>(
            'printstring',
            '$clampedSize///$paperMm///$text',
          ) ??
          false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Write string failed: $e');
      return false;
    }
  }

  /// Resets printer layout for the selected paper width (call once per receipt).
  static Future<bool> initPaperLayout(ThermalPaperSize paperSize) async {
    try {
      return await _channel.invokeMethod<bool>(
            'initpaper',
            paperSize.widthMm,
          ) ??
          false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Init paper layout failed: $e');
      return false;
    }
  }
}
