import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/invoice_labels.dart';
import '../models/printer_settings.dart';

class InvoicePrintContext {
  final String? clientAddress;
  final String? clientPhone;
  final Map<String, Map<String, dynamic>> productDetailsByName;

  const InvoicePrintContext({
    this.clientAddress,
    this.clientPhone,
    this.productDetailsByName = const {},
  });
}

class _InvoiceWhen {
  final String date;
  final String time;

  const _InvoiceWhen({required this.date, required this.time});
}

class _ReceiptColumns {
  final int width;
  final int product;
  final int qty;
  final int price;
  final int total;

  const _ReceiptColumns({
    required this.width,
    required this.product,
    required this.qty,
    required this.price,
    required this.total,
  });

  factory _ReceiptColumns.forPaper(ThermalPaperSize paper) {
    final w = paper.charsPerLine;
    if (w <= 32) {
      return _ReceiptColumns(
        width: w,
        product: 13,
        qty: 5,
        price: 6,
        total: 8,
      );
    }
    return _ReceiptColumns(
      width: w,
      product: 20,
      qty: 6,
      price: 8,
      total: w - 34,
    );
  }
}

class InvoicePrintFormatter {
  static final _money = NumberFormat('#,##0.00', 'en_US');

  static String format({
    required Map<String, dynamic> invoice,
    required PrinterSettings settings,
    InvoicePrintContext context = const InvoicePrintContext(),
  }) {
    final labels = settings.labels;
    final pad = settings.rightMargin > 0 ? ' ' * settings.rightMargin : '';
    final cols = _ReceiptColumns.forPaper(settings.paperSize);
    final sep = '-' * cols.width;
    final buffer = StringBuffer();

    void line(String text) => buffer.writeln('$pad$text');

    // ── Header (centered) ──
    for (final part in _headerLines(settings)) {
      line(_center(part, cols.width));
    }
    final title = invoice['invoiceType']?.toString() == 'return'
        ? 'فاتورة مرتجع'
        : labels.invoiceTitle;
    line(_center(title, cols.width));
    line(sep);

    // ── Metadata (two columns) ──
    final when = _parseDateTime(invoice['date']);
    final typeLabel = _paymentTypeLabel(invoice['paymentMethod']);
    final invoiceNo = invoice['invoiceNumber']?.toString() ?? '';

    line(_twoColumn(
      cols.width,
      'النوع : $typeLabel',
      'الرقم : $invoiceNo',
    ));
    line(_twoColumn(
      cols.width,
      'التاريخ : ${when.date}',
      'الوقت : ${when.time}',
    ));
    line(sep);

    // ── Customer ──
    line(_center('اسم العميل', cols.width));
    line(_center(invoice['clientName']?.toString() ?? '', cols.width));

    if (settings.showCustomerAddressAndPhone) {
      final address = context.clientAddress?.trim() ?? '';
      final phone = context.clientPhone?.trim() ?? '';
      if (address.isNotEmpty) {
        line(_center('${labels.address}: $address', cols.width));
      }
      if (phone.isNotEmpty) {
        line(_center('${labels.phone}: $phone', cols.width));
      }
    }

    line(sep);

    // ── Items table (left → right: اسم المنتج | الكمية | السعر | الإجمالي) ──
    line(_tableRow(
      cols,
      'اسم المنتج',
      'الكمية',
      'السعر',
      'الإجمالي',
    ));
    line(sep);

    final products = invoice['products'] as List<dynamic>? ?? [];
    var qtySum = 0.0;
    for (final item in products) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = map['product']?.toString() ?? '';
      final qtyStr = map['amount']?.toString() ?? '0';
      qtySum += _num(qtyStr);
      final price = _formatMoney(_num(map['selectedPrice']));
      final total = _formatMoney(_num(map['total']));

      _writeProductRow(
        line,
        cols: cols,
        name: name,
        qty: qtyStr,
        price: price,
        total: total,
      );

      final details = context.productDetailsByName[name] ?? {};
      _appendProductExtras(
        buffer,
        pad: pad,
        cols: cols,
        map: map,
        details: details,
        settings: settings,
        labels: labels,
      );
    }

    line(sep);
    line(_tableRow(
      cols,
      '',
      _formatQty(qtySum),
      '',
      '',
    ));
    line(sep);

    // ── Totals ──
    final previous = _num(invoice['previousBalance']);
    final totalSum = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = _num(invoice['balance']);

    line(_summaryRow(cols.width, labels.previousBalance, previous));
    line(_summaryRow(cols.width, 'إجمالي ف.', totalSum));
    line(_summaryRow(cols.width, labels.paid, paid));
    line(_summaryRow(
      cols.width,
      'الرصيد الحالي (عليكم)',
      balance,
    ));

    if (settings.showTaxQrOnInvoice) {
      line(sep);
      line(_center('QR الضريبة: #$invoiceNo', cols.width));
    }

    final notes = invoice['notes']?.toString() ?? '';
    if (notes.isNotEmpty) {
      line(sep);
      line(_center('ملاحظات: $notes', cols.width));
    }

    return buffer.toString();
  }

  static List<String> _headerLines(PrinterSettings settings) {
    final lines = <String>[];
    final name = settings.receiptStoreName.trim();
    if (name.isNotEmpty) lines.add(name);
    final address = settings.receiptStoreAddress.trim();
    if (address.isNotEmpty) lines.add(address);
    final phone = settings.receiptStorePhone.trim();
    if (phone.isNotEmpty) lines.add(phone);
    if (lines.isEmpty) {
      lines.add('أبو مجدي للحدايد والعدد والديكور والخشب والحلايا');
      lines.add('كفر الزيات - طنطا - الغربية');
      lines.add('01010573888');
    }
    return lines;
  }

  static void _appendProductExtras(
    StringBuffer buffer, {
    required String pad,
    required _ReceiptColumns cols,
    required Map<String, dynamic> map,
    required Map<String, dynamic> details,
    required PrinterSettings settings,
    required InvoiceLabels labels,
  }) {
    void extra(String text) => buffer.writeln('$pad  $text');

    if (settings.showProductDescription) {
      final desc = map['description']?.toString() ??
          details['description']?.toString() ??
          '';
      if (desc.isNotEmpty) extra('${labels.description}: $desc');
    }

    if (settings.showProductNumberOnA4) {
      final num = map['randomNumber']?.toString() ??
          details['randomNumber']?.toString() ??
          '';
      if (num.isNotEmpty) extra('${labels.productNumber}: $num');
    }

    if (settings.showExpiryDateOnA4) {
      final expiry = map['expiryDate'];
      if (expiry != null) {
        String expiryStr;
        try {
          expiryStr = expiry.toDate().toLocal().toString().split(' ')[0];
        } catch (_) {
          expiryStr = expiry.toString();
        }
        extra('${labels.expiryDate}: $expiryStr');
      }
    }

    if (settings.showProductImageOnInvoice) {
      final image = map['image']?.toString() ??
          details['image']?.toString() ??
          '';
      if (image.isNotEmpty) extra('[${labels.product} صورة]');
    }
  }

  static String _center(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final pad = width - text.length;
    final left = pad ~/ 2;
    return '${' ' * left}$text${' ' * (pad - left)}';
  }

  static String _twoColumn(int width, String right, String left) {
    final gap = width - right.length - left.length;
    if (gap < 1) return '$right\n$left';
    return '$right${' ' * gap}$left';
  }

  static String _summaryRow(int width, String label, double amount) {
    final value = _formatMoney(amount);
    return _twoColumn(width, '$label :', value);
  }

  /// Mixed Arabic/Latin in one row breaks thermal column alignment — use two lines.
  static void _writeProductRow(
    void Function(String text) line, {
    required _ReceiptColumns cols,
    required String name,
    required String qty,
    required String price,
    required String total,
  }) {
    if (_shouldSplitProductRow(name, cols.product)) {
      for (final wrapLine in _wrapProductName(name, cols.width)) {
        line(wrapLine);
      }
      line(_tableRow(cols, '', qty, price, total));
    } else {
      line(_tableRow(cols, name, qty, price, total));
    }
  }

  static bool _shouldSplitProductRow(String name, int productColWidth) {
    if (name.isEmpty) return false;
    if (name.length > productColWidth) return true;
    return _hasMixedArabicAndLatin(name);
  }

  static bool _hasMixedArabicAndLatin(String text) {
    var hasArabic = false;
    var hasLatin = false;
    for (final code in text.runes) {
      if (_isArabicRune(code)) {
        hasArabic = true;
      } else if (_isLatinOrDigitRune(code)) {
        hasLatin = true;
      }
      if (hasArabic && hasLatin) return true;
    }
    return false;
  }

  static bool _isArabicRune(int code) {
    return (code >= 0x0600 && code <= 0x06FF) ||
        (code >= 0x0750 && code <= 0x077F) ||
        (code >= 0x08A0 && code <= 0x08FF) ||
        (code >= 0xFB50 && code <= 0xFDFF) ||
        (code >= 0xFE70 && code <= 0xFEFF);
  }

  static bool _isLatinOrDigitRune(int code) {
    return (code >= 0x0041 && code <= 0x005A) ||
        (code >= 0x0061 && code <= 0x007A) ||
        (code >= 0x0030 && code <= 0x0039);
  }

  static List<String> _wrapProductName(String name, int maxWidth) {
    if (name.length <= maxWidth) return [name];
    final lines = <String>[];
    var remaining = name.trim();
    while (remaining.isNotEmpty) {
      if (remaining.length <= maxWidth) {
        lines.add(remaining);
        break;
      }
      var breakAt = remaining.lastIndexOf(' ', maxWidth);
      if (breakAt <= 0) breakAt = maxWidth;
      lines.add(remaining.substring(0, breakAt).trim());
      remaining = remaining.substring(breakAt).trim();
    }
    return lines.isEmpty ? [name] : lines;
  }

  static String _tableRow(
    _ReceiptColumns cols,
    String product,
    String qty,
    String price,
    String total,
  ) {
    return _col(product, cols.product) +
        _col(qty, cols.qty, right: true) +
        _col(price, cols.price, right: true) +
        _col(total, cols.total, right: true);
  }

  static String _col(String text, int width, {bool right = false}) {
    var t = text;
    if (t.length > width) t = t.substring(0, width);
    return right ? t.padLeft(width) : t.padRight(width);
  }

  static String _formatMoney(double value) => _money.format(value);

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(1);
  }

  static String _paymentTypeLabel(dynamic method) {
    final m = method?.toString().trim() ?? '';
    if (m.isEmpty) return 'نقد';
    if (m.contains('آجل') || m.contains('اجل')) return 'اجل';
    if (m.contains('نقد')) return 'نقد';
    if (m.contains('بطاق')) return 'بطاقه';
    return m;
  }

  static _InvoiceWhen _parseDateTime(dynamic date) {
    DateTime? dt;
    if (date is Timestamp) {
      dt = date.toDate().toLocal();
    } else if (date is DateTime) {
      dt = date.toLocal();
    }
    if (dt == null) {
      return const _InvoiceWhen(date: '', time: '');
    }
    final d = dt;
    return _InvoiceWhen(
      date:
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}',
      time:
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}',
    );
  }

  /// Plain-text test slip (matches [BluetoothPrinterService.printTestReceipt]).
  static String buildPrinterTestPreview(PrinterSettings settings) {
    final buffer = StringBuffer();
    for (final part in _headerLines(settings)) {
      buffer.writeln(part);
    }
    buffer.writeln('اختبار الطابعة');
    final deviceLabel = settings.bluetoothDeviceName.isNotEmpty
        ? settings.bluetoothDeviceName
        : settings.bluetoothMacAddress;
    if (deviceLabel.isNotEmpty) {
      buffer.writeln(deviceLabel);
    }
    if (settings.salesInvoiceFooter.isNotEmpty) {
      buffer.writeln('-' * settings.paperSize.charsPerLine);
      buffer.writeln(settings.salesInvoiceFooter);
    }
    return buffer.toString().trimRight();
  }

  static Map<String, dynamic> _sampleSalesInvoice() {
    return {
      'invoiceNumber': 6,
      'date': DateTime(2024, 2, 26, 14, 49, 5),
      'clientName': 'عيد مطروح',
      'paymentMethod': 'آجل',
      'previousBalance': 0.0,
      'totalSum': 25760.0,
      'paidAmount': 0.0,
      'balance': 6470.80,
      'products': [
        {
          'product': 'كيلو شمبر كمبيوتر',
          'amount': '300',
          'selectedPrice': 50.0,
          'total': 15000.0,
        },
      ],
    };
  }

  /// Sample sales invoice using current label/footer/toggle settings.
  static String buildSampleSalesInvoicePreview(PrinterSettings settings) {
    final body = format(
      invoice: _sampleSalesInvoice(),
      settings: settings,
      context: const InvoicePrintContext(),
    );
    if (settings.salesInvoiceFooter.isEmpty) return body;
    return '$body${'-' * settings.paperSize.charsPerLine}\n${settings.salesInvoiceFooter}\n';
  }

  /// Full on-screen preview: test slip + sample invoice.
  static String buildFullReceiptPreview(PrinterSettings settings) {
    final paperLabel =
        settings.paperSize == ThermalPaperSize.mm58 ? '58mm' : '80mm';
    final buffer = StringBuffer();
    buffer.writeln('══════════════════════════════');
    buffer.writeln('معاينة الإيصال ($paperLabel)');
    buffer.writeln('للاختبار بدون طابعة بلوتوث');
    buffer.writeln('══════════════════════════════');
    buffer.writeln();
    buffer.writeln('── اختبار الطابعة ──');
    buffer.writeln(buildPrinterTestPreview(settings));
    buffer.writeln();
    buffer.writeln('── فاتورة مبيعات (نموذج) ──');
    buffer.write(buildSampleSalesInvoicePreview(settings));
    buffer.writeln();
    buffer.writeln('══════════════════════════════');
    return buffer.toString();
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
