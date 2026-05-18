import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Opens WhatsApp with image (+ optional caption) for a specific phone on Android.
class WhatsappShareChannel {
  WhatsappShareChannel._();

  static const MethodChannel _channel = MethodChannel('kareem.store/whatsapp');

  static Future<bool> shareImage({
    required String phoneDigits,
    required String imagePath,
    String? caption,
  }) async {
    if (!Platform.isAndroid) {
      return _shareImageFallback(imagePath, caption);
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

    return _shareImageFallback(imagePath, caption);
  }

  static Future<bool> _shareImageFallback(
    String imagePath,
    String? caption,
  ) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: caption,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
