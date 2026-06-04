import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppErrorSeverity { warning, error, fatal }

/// Saves app errors to Firestore collection [app_errors] for remote debugging.
class AppErrorLogger {
  static const String collectionName = 'app_errors';
  static const String _appVersion = '1.0.0+1';
  static const int _maxStackLength = 12000;
  static const int _debounceMs = 20000;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Map<String, int> _debounce = {};

  /// Call once after [Firebase.initializeApp].
  static void installGlobalHandlers() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousFlutterHandler?.call(details);
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
      record(
        error: details.exception,
        stackTrace: details.stack,
        step: 'flutter_framework',
        severity: AppErrorSeverity.fatal,
        metadata: {
          'summary': details.summary.toString(),
          if (details.library != null) 'library': details.library!,
          if (details.context != null) 'context': details.context.toString(),
        },
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(
        error: error,
        stackTrace: stack,
        step: 'platform_dispatcher',
        severity: AppErrorSeverity.fatal,
      );
      return true;
    };
  }

  /// Logs an exception (and optional context) to Firestore without blocking UI.
  static Future<void> record({
    required Object error,
    StackTrace? stackTrace,
    required String step,
    AppErrorSeverity severity = AppErrorSeverity.error,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final message = error.toString();
      final dedupeKey = '$step|$severity|$message';
      if (_isDuplicate(dedupeKey)) return;

      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('user_role');
      final userEmail = prefs.getString('user_email');

      final payload = <String, dynamic>{
        'message': message,
        'errorType': error.runtimeType.toString(),
        'stackTrace': _truncateStack(stackTrace),
        'step': step,
        'severity': severity.name,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
        'appVersion': _appVersion,
        'createdAt': FieldValue.serverTimestamp(),
        if (userRole != null && userRole.isNotEmpty) 'userRole': userRole,
        if (userEmail != null && userEmail.isNotEmpty) 'userEmail': userEmail,
        if (metadata != null && metadata.isNotEmpty)
          'metadata': _sanitizeMetadata(metadata),
      };

      unawaited(_writeToFirestore(payload));
    } catch (e) {
      debugPrint('AppErrorLogger.record failed: $e');
    }
  }

  /// Non-throwing failures (e.g. printer connect returned false).
  static void logFailure({
    required String step,
    required String message,
    AppErrorSeverity severity = AppErrorSeverity.warning,
    Map<String, dynamic>? metadata,
  }) {
    record(
      error: Exception(message),
      step: step,
      severity: severity,
      metadata: metadata,
    );
  }

  /// Runs [action]; on error logs to Firestore and returns [onError].
  static Future<T?> guard<T>(
    String step,
    Future<T> Function() action, {
    T? onError,
    Map<String, dynamic>? metadata,
    AppErrorSeverity severity = AppErrorSeverity.error,
  }) async {
    try {
      return await action();
    } catch (e, st) {
      await record(
        error: e,
        stackTrace: st,
        step: step,
        severity: severity,
        metadata: metadata,
      );
      return onError;
    }
  }

  static Future<void> _writeToFirestore(Map<String, dynamic> payload) async {
    try {
      await _firestore.collection(collectionName).add(payload);
    } catch (e) {
      debugPrint('AppErrorLogger Firestore write failed: $e');
    }
  }

  static bool _isDuplicate(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _debounce[key];
    if (last != null && now - last < _debounceMs) return true;
    _debounce[key] = now;
    if (_debounce.length > 200) {
      _debounce.removeWhere((_, t) => now - t > _debounceMs);
    }
    return false;
  }

  static String? _truncateStack(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final text = stackTrace.toString();
    if (text.length <= _maxStackLength) return text;
    return '${text.substring(0, _maxStackLength)}\n…(truncated)';
  }

  static Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      if (value is String ||
          value is num ||
          value is bool ||
          value is Timestamp) {
        out[key] = value;
      } else if (value is Map) {
        out[key] = value.map((k, v) => MapEntry(k.toString(), v?.toString()));
      } else if (value is Iterable) {
        out[key] = value.map((e) => e.toString()).toList();
      } else {
        out[key] = value.toString();
      }
    });
    return out;
  }
}
