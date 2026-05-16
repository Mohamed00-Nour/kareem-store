import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/paired_bluetooth_device.dart';

/// Dart bridge to the native code shipped by [print_bluetooth_thermal].
class ThermalPrintChannel {
  ThermalPrintChannel._();

  static const MethodChannel _channel =
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

  static Future<List<PairedBluetoothDevice>> pairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('pairedbluetooths');
      if (result == null) return [];
      return result.map((item) {
        final parts = item.toString().split('#');
        return PairedBluetoothDevice(
          name: parts.isNotEmpty ? parts[0] : '',
          macAddress: parts.length > 1 ? parts[1] : '',
        );
      }).toList();
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
    try {
      return await _channel.invokeMethod<bool>('connect', macAddress) ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Bluetooth connect failed: $e');
      return false;
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

  static Future<bool> writeString({required int size, required String text}) async {
    final clampedSize = size.clamp(1, 5);
    try {
      return await _channel.invokeMethod<bool>(
            'printstring',
            '$clampedSize///$text',
          ) ??
          false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Write string failed: $e');
      return false;
    }
  }
}
