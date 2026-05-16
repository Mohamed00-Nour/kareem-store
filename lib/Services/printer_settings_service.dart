import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_settings.dart';

class PrinterSettingsService {
  static const _storageKeyV2 = 'printer_settings_v2';
  static const _storageKeyV1 = 'printer_settings_v1';

  static Future<PrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_storageKeyV2);
    raw ??= prefs.getString(_storageKeyV1);
    if (raw == null) return const PrinterSettings();
    try {
      return PrinterSettings.fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PrinterSettings();
    }
  }

  static Future<void> save(PrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKeyV2, jsonEncode(settings.toMap()));
  }
}
