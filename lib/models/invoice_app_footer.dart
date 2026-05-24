/// Mandatory branding footer on invoices (print, PDF, WhatsApp image).
class InvoiceAppFooter {
  InvoiceAppFooter._();

  static const String branding =
      'برمجة شركة easy app م/محمد خالد: 01126697513';

  /// Optional custom footer from printer settings, plus [branding].
  static String resolve([String? settingsFooter]) {
    final custom = settingsFooter?.trim() ?? '';
    if (custom.isEmpty) return branding;
    if (custom.contains(branding)) return custom;
    return '$custom\n$branding';
  }

  static List<String> resolveLines([String? settingsFooter]) {
    return resolve(settingsFooter)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }
}
