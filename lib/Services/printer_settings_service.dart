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

  static PrinterSettings? _cachedSettings;

  /// Returns currently cached PrinterSettings immediately from memory or SharedPreferences.
  static PrinterSettings get current {
    return _cachedSettings ?? const PrinterSettings();
  }

  static PrinterSettings _loadFromPrefs(SharedPreferences prefs) {
    var raw = prefs.getString(_storageKeyV2);
    raw ??= prefs.getString(_storageKeyV1);
    if (raw == null) return const PrinterSettings();
    try {
      final settings = PrinterSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      _cachedSettings = settings;
      return settings;
    } catch (_) {
      return const PrinterSettings();
    }
  }

  /// Initializes local cache from SharedPreferences. Call during app startup.
  static Future<PrinterSettings> initLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _loadFromPrefs(prefs);
    _cachedSettings = settings;
    return settings;
  }

  static Future<PrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var localSettings = _loadFromPrefs(prefs);

    try {
      final docSnap = await _firestoreDoc.get().timeout(const Duration(seconds: 3));
      if (docSnap.exists && docSnap.data() != null) {
        final remoteData = Map<String, dynamic>.from(docSnap.data()!);
        final remoteSettings = PrinterSettings.fromMap(remoteData);
        final merged = remoteSettings.copyWith(
          receiptLogoPath: localSettings.receiptLogoPath,
        );

        // Cache merged settings locally in SharedPreferences and memory
        _cachedSettings = merged;
        await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
        return merged;
      }
    } catch (_) {
      // Offline or timeout — return cached local settings
    }

    _cachedSettings = localSettings;
    return localSettings;
  }

  static Future<void> save(PrinterSettings settings) async {
    _cachedSettings = settings;
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

  /// Returns a stream that IMMEDIATELY emits cached SharedPreferences settings,
  /// then updates SharedPreferences and emits new data whenever Firestore changes.
  static Stream<PrinterSettings> stream() {
    late StreamController<PrinterSettings> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;

    controller = StreamController<PrinterSettings>.broadcast(
      onListen: () async {
        final prefs = await SharedPreferences.getInstance();
        final localSettings = _loadFromPrefs(prefs);
        _cachedSettings = localSettings;
        if (!controller.isClosed) {
          controller.add(localSettings);
        }

        sub = _firestoreDoc.snapshots().listen(
          (docSnap) async {
            if (docSnap.exists && docSnap.data() != null) {
              final remoteData = Map<String, dynamic>.from(docSnap.data()!);
              final remoteSettings = PrinterSettings.fromMap(remoteData);
              final currentLocal = _loadFromPrefs(prefs);
              final merged = remoteSettings.copyWith(
                receiptLogoPath: currentLocal.receiptLogoPath,
              );
              _cachedSettings = merged;
              await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
              if (!controller.isClosed) {
                controller.add(merged);
              }
            }
          },
          onError: (_) {
            // Network error offline — keep local settings in stream
          },
        );
      },
      onCancel: () {
        sub?.cancel();
      },
    );

    return controller.stream;
  }
}
