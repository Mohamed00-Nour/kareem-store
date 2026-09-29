import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_settings.dart';
import '../sync/firestore_read_diagnostics.dart';

class PrinterSettingsService {
  static const _storageKeyV2 = 'printer_settings_v2';
  static const _storageKeyV1 = 'printer_settings_v1';
  static final _firestoreDoc =
      FirebaseFirestore.instance.collection('settings').doc('printer_settings');

  static PrinterSettings? _cachedSettings;
  static StreamController<PrinterSettings>? _controller;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _subscription;
  static bool _startingStream = false;
  static bool _hasStreamConsumers = false;

  static PrinterSettings get current =>
      _cachedSettings ?? const PrinterSettings();

  static PrinterSettings _loadFromPrefs(SharedPreferences prefs) {
    var raw = prefs.getString(_storageKeyV2);
    raw ??= prefs.getString(_storageKeyV1);
    if (raw == null) return const PrinterSettings();
    try {
      final settings =
          PrinterSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      _cachedSettings = settings;
      return settings;
    } catch (_) {
      return const PrinterSettings();
    }
  }

  static Future<PrinterSettings> initLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _loadFromPrefs(prefs);
    _cachedSettings = settings;
    return settings;
  }

  static Future<PrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localSettings = _loadFromPrefs(prefs);

    try {
      final docSnap =
          await _firestoreDoc.get().timeout(const Duration(seconds: 3));
      FirestoreReadDiagnostics.queryResult(
        'settings/printer_settings',
        docSnap.exists ? 1 : 0,
        trigger: 'printer settings load',
        fromCache: docSnap.metadata.isFromCache,
      );
      if (docSnap.exists && docSnap.data() != null) {
        final remoteData = Map<String, dynamic>.from(docSnap.data()!);
        final remoteSettings = PrinterSettings.fromMap(remoteData);
        final merged = remoteSettings.copyWith(
          receiptLogoPath: localSettings.receiptLogoPath,
        );
        _cachedSettings = merged;
        await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
        return merged;
      }
    } catch (_) {
      // Offline or timeout: keep the device cache.
    }

    _cachedSettings = localSettings;
    return localSettings;
  }

  static Future<void> save(PrinterSettings settings) async {
    _cachedSettings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKeyV2, jsonEncode(settings.toMap()));

    try {
      final remoteMap = settings.toMap()..remove('receiptLogoPath');
      await _firestoreDoc.set(remoteMap, SetOptions(merge: true));
    } catch (_) {
      // Local settings remain available while offline.
    }
  }

  /// A stable shared stream prevents parent rebuilds and multiple widgets from
  /// creating duplicate Firestore listeners for the same one-document source.
  static Stream<PrinterSettings> stream() {
    _controller ??= StreamController<PrinterSettings>.broadcast(
      onListen: _onStreamListen,
      onCancel: _onStreamCancel,
    );
    return _controller!.stream;
  }

  static void _onStreamListen() {
    _hasStreamConsumers = true;
    unawaited(_startStream());
  }

  static void _onStreamCancel() {
    _hasStreamConsumers = false;
    _stopStream();
  }

  static Future<void> _startStream() async {
    if (_subscription != null || _startingStream) return;
    _startingStream = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // The last widget may have unsubscribed while preferences were loading.
      // In that case an upstream listener would have no owner and could live
      // until process shutdown.
      if (!_hasStreamConsumers) return;
      final localSettings = _loadFromPrefs(prefs);
      _cachedSettings = localSettings;
      _controller?.add(localSettings);

      const identity = 'settings/printer_settings';
      const trigger = 'shared printer settings listener';
      FirestoreReadDiagnostics.listenerAttached(identity, trigger: trigger);
      _subscription = _firestoreDoc.snapshots().listen(
        (docSnap) async {
          FirestoreReadDiagnostics.listenerSnapshot(
            identity,
            docSnap.exists ? 1 : 0,
            trigger: trigger,
            fromCache: docSnap.metadata.isFromCache,
            changes: docSnap.exists ? 1 : 0,
          );
          if (!docSnap.exists || docSnap.data() == null) return;
          final remoteData = Map<String, dynamic>.from(docSnap.data()!);
          final remoteSettings = PrinterSettings.fromMap(remoteData);
          final currentLocal = _loadFromPrefs(prefs);
          final merged = remoteSettings.copyWith(
            receiptLogoPath: currentLocal.receiptLogoPath,
          );
          _cachedSettings = merged;
          await prefs.setString(_storageKeyV2, jsonEncode(merged.toMap()));
          _controller?.add(merged);
        },
        onError: (Object error) {
          FirestoreReadDiagnostics.queryError(
            identity,
            error,
            trigger: trigger,
          );
        },
      );
    } finally {
      _startingStream = false;
    }
  }

  static void _stopStream() {
    final subscription = _subscription;
    _subscription = null;
    if (subscription == null) return;
    unawaited(subscription.cancel());
    FirestoreReadDiagnostics.listenerDetached(
      'settings/printer_settings',
      trigger: 'shared printer settings listener',
    );
  }
}
