import 'dart:io';
import '../models/printer_settings.dart';

class HeaderHelper {
  /// Returns non-empty header lines (store name, store address, phone numbers).
  /// If fields are empty, returns an empty list (no hardcoded fallbacks).
  static List<String> getHeaderLines(PrinterSettings settings) {
    final lines = <String>[];
    
    final name = settings.receiptStoreName.trim();
    if (name.isNotEmpty) {
      lines.add(name);
    }
    
    final address = settings.receiptStoreAddress.trim();
    if (address.isNotEmpty) {
      lines.add(address);
    }
    
    final phoneRaw = settings.receiptStorePhone.trim();
    if (phoneRaw.isNotEmpty) {
      final phoneLines = phoneRaw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      lines.addAll(phoneLines);
    }
    
    return lines;
  }

  /// Returns logo [File] if custom logo exists in settings, otherwise null.
  static File? getLogoFile(PrinterSettings settings) {
    final path = settings.receiptLogoPath.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }
}
