import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_settings.dart';

class PrinterSettingsService {
  static const _storageKeyV2 = 'printer_settings_v2';
  static const _storageKeyV1 = 'printer_settings_v1';
  static final _firestoreDoc =
      FirebaseFirestore.instance.collection('settings').doc('printer_settings');

  static PrinterSettings _loadFromPrefs(SharedPreferences prefs) {
    var raw = prefs.getString(_storageKeyV2);
    raw ??= prefs.getString(_storageKeyV1);
    if (raw == null) return const PrinterSettings();
    try {
      return PrinterSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PrinterSettings();
    }
  }

  static Future<PrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var localSettings = _loadFromPrefs(prefs);

    try {
      final docSnap = await _firestoreDoc.get().timeout(const Duration(seconds: 3));
      if (docSnap.exists && docSnap.data() != null) {
        final remoteData = Map<String, dynamic>.from(docSnap.data()!);
        // Merge remote fields into local settings while preserving local device logo path
        final remoteSettings = PrinterSettings.fromMap(remoteData);
        final merged = remoteSettings.copyWith(
          receiptLogoPath: localSettings.receiptLogoPath,
        );

        // Cache merged settings locally
        await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
        return merged;
      }
    } catch (_) {
      // Offline or timeout — return cached local settings
    }

    return localSettings;
  }

  static Future<void> save(PrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKeyV2, jsonEncode(settings.toMap()));

    try {
      final remoteMap = settings.toMap();
      // Remove local file path before uploading so device-specific path isn't forced on others
      remoteMap.remove('receiptLogoPath');
      await _firestoreDoc.set(remoteMap, SetOptions(merge: true));
    } catch (_) {
      // Ignore network errors when offline; local save succeeded
    }
  }

  static Stream<PrinterSettings> stream() {
    return _firestoreDoc.snapshots().asyncMap((docSnap) async {
      final prefs = await SharedPreferences.getInstance();
      final localSettings = _loadFromPrefs(prefs);

      if (docSnap.exists && docSnap.data() != null) {
        final remoteData = Map<String, dynamic>.from(docSnap.data()!);
        final remoteSettings = PrinterSettings.fromMap(remoteData);
        final merged = remoteSettings.copyWith(
          receiptLogoPath: localSettings.receiptLogoPath,
        );
        await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
        return merged;
      }
      return localSettings;
    });
  }
}
