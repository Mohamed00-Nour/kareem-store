import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Opens WhatsApp with image(s) (+ optional caption) for a specific phone on Android.
class WhatsappShareChannel {
  WhatsappShareChannel._();

  static const MethodChannel _channel = MethodChannel('kareem.store/whatsapp');

  static Future<bool> shareImage({
    required String phoneDigits,
    required String imagePath,
    String? caption,
  }) =>
      shareImages(
        phoneDigits: phoneDigits,
        imagePaths: [imagePath],
        caption: caption,
      );

  static Future<bool> shareImages({
    required String phoneDigits,
    required List<String> imagePaths,
    String? caption,
  }) async {
    final paths =
        imagePaths.where((p) => p.trim().isNotEmpty).toList(growable: false);
    if (paths.isEmpty) return false;
    if (paths.length == 1) {
      return _shareSingle(phoneDigits, paths.first, caption);
    }

    if (!Platform.isAndroid) {
      return _shareImagesFallback(paths, caption);
    }

    try {
      final ok = await _channel.invokeMethod<bool>('shareImages', {
            'phone': phoneDigits,
            'paths': paths,
            'text': caption ?? '',
          }) ??
          false;
      if (ok) return true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('WhatsappShareChannel: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('WhatsappShareChannel: $e');
    }

    return _shareImagesFallback(paths, caption);
  }

  static Future<bool> _shareSingle(
    String phoneDigits,
    String imagePath,
    String? caption,
  ) async {
    if (!Platform.isAndroid) {
      return _shareImagesFallback([imagePath], caption);
    }

    try {
      final ok = await _channel.invokeMethod<bool>('shareImage', {
            'phone': phoneDigits,
            'path': imagePath,
            'text': caption ?? '',
          }) ??
          false;
      if (ok) return true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('WhatsappShareChannel: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('WhatsappShareChannel: $e');
    }

    return _shareImagesFallback([imagePath], caption);
  }

  static Future<bool> _shareImagesFallback(
    List<String> imagePaths,
    String? caption,
  ) async {
    try {
      await Share.shareXFiles(
        imagePaths.map((p) => XFile(p)).toList(),
        text: caption,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
