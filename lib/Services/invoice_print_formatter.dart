import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/invoice_app_footer.dart';
import '../models/invoice_labels.dart';
import '../models/invoice_receipt_print_data.dart';
import '../models/printer_settings.dart';
import 'invoice_number_utils.dart';

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
  final int rowNum;
  final int product;
  final int qty;
  final int price;
  final int total;

  const _ReceiptColumns({
    required this.width,
    required this.rowNum,
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
        rowNum: 3,
        total: 6,
        price: 5,
        qty: 3,
        product: w - 17,
      );
    }
    return _ReceiptColumns(
      width: w,
      rowNum: 3,
      total: 7,
      price: 6,
      qty: 4,
      product: w - 20,
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

    // ── Customer (one line) ──
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    if (clientName.isNotEmpty) {
      line(_center('اسم العميل : $clientName', cols.width));
    }

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

    // ── Items (RTL: الإجمالي | السعر | الكمية | المنتج | م) — one line per item ──
    line(_tableRow(
      cols,
      rowNum: 'م',
      total: 'الإجمالي',
      price: 'السعر',
      qty: 'الكمية',
      product: 'اسم المنتج',
    ));
    line(_tableRule(cols));

    final products = invoice['products'] as List<dynamic>? ?? [];
    var qtySum = 0.0;
    var textRowIndex = 0;
    for (final item in products) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = invoiceProductName(map);
      final qtyStr = _formatQty(_num(map['amount']));
      qtySum += _num(map['amount']);
      textRowIndex++;
      final price = _formatMoneyCompact(_num(map['selectedPrice']));
      final total = _formatMoneyCompact(_num(map['total']));

      _writeProductRow(
        line,
        cols: cols,
        rowNum: '$textRowIndex',
        name: name,
        qty: qtyStr,
        price: price,
        total: total,
        separateNameLine: settings.printProductNameOnSeparateLine,
      );

      if (settings.showProductDescription ||
          settings.showProductNumberOnA4 ||
          settings.showExpiryDateOnA4 ||
          settings.showProductImageOnInvoice) {
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
    }

    line(sep);
    line(_center(_formatQty(qtySum), cols.width));
    line(sep);

    // ── Totals ──
    final previous = _num(invoice['previousBalance']);
    final totalSum = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = invoiceClientRemainingOwed(invoice);

    line(_summaryRow(cols.width, labels.previousBalance, previous));
    line(_summaryRow(cols.width, 'إجمالي ف.', totalSum));
    line(_summaryRow(cols.width, labels.paid, paid));
    line(_summaryRow(cols.width, 'المتبقي من الفاتورة', totalSum - paid));
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

    line(sep);
    for (final footerLine in InvoiceAppFooter.resolveLines(settings.salesInvoiceFooter)) {
      line(_center(footerLine, cols.width));
    }

    return buffer.toString();
  }

  /// Payload for native bordered-table thermal print (Bluetooth).
  static InvoiceReceiptPrintData buildReceiptPrintData({
    required Map<String, dynamic> invoice,
    required PrinterSettings settings,
    InvoicePrintContext context = const InvoicePrintContext(),
  }) {
    final labels = settings.labels;
    final cols = _ReceiptColumns.forPaper(settings.paperSize);
    final when = _parseDateTime(invoice['date']);
    final typeLabel = _paymentTypeLabel(invoice['paymentMethod']);
    final invoiceNo = invoice['invoiceNumber']?.toString() ?? '';
    final title = invoice['invoiceType']?.toString() == 'return'
        ? 'فاتورة مرتجع'
        : labels.invoiceTitle;

    final centered = <String>[
      'أبو مجدي للحدايد والعدد والديكور والخشب والحلايا',
      'كفر الزيات - طنطا - الغربية',
      title,
      'مجدي حماد: 01010573888 - 01201820045',
      'كريم حماد: 01068462105 - 01207968495',
    ];

    final metaTable = <List<String>>[
      ['الرقم', invoiceNo, 'النوع', typeLabel],
      ['التاريخ', when.date, 'الوقت', when.time],
    ];

    final body = <String>[];
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    if (clientName.isNotEmpty) {
      body.add(_center('اسم العميل : $clientName', cols.width));
    }
    if (settings.showCustomerAddressAndPhone) {
      final address = context.clientAddress?.trim() ?? '';
      final phone = context.clientPhone?.trim() ?? '';
      if (address.isNotEmpty) {
        body.add(_center('${labels.address}: $address', cols.width));
      }
      if (phone.isNotEmpty) {
        body.add(_center('${labels.phone}: $phone', cols.width));
      }
    }

    final tableRows = <InvoiceReceiptTableRow>[];
    final products = invoice['products'] as List<dynamic>? ?? [];
    var qtySum = 0.0;
    var rowIndex = 0;
    for (final item in products) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = invoiceProductName(map);
      qtySum += _num(map['amount']);
      rowIndex++;
      final extras = <String>[];
      if (settings.showProductDescription ||
          settings.showProductNumberOnA4 ||
          settings.showExpiryDateOnA4 ||
          settings.showProductImageOnInvoice) {
        final details = context.productDetailsByName[name] ?? {};
        final extraBuffer = StringBuffer();
        _appendProductExtras(
          extraBuffer,
          pad: '',
          cols: cols,
          map: map,
          details: details,
          settings: settings,
          labels: labels,
        );
        for (final line in extraBuffer.toString().split('\n')) {
          final t = line.trim();
          if (t.isNotEmpty) extras.add(t);
        }
      }
      tableRows.add(
        InvoiceReceiptTableRow(
          rowNum: '$rowIndex',
          product: name,
          qty: _formatQty(_num(map['amount'])),
          price: _formatMoney(_num(map['selectedPrice'])),
          total: _formatMoney(_num(map['total'])),
          extraLines: extras,
        ),
      );
    }

    final previous = _num(invoice['previousBalance']);
    final totalSum = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = invoiceClientRemainingOwed(invoice);

    final summaryTable = <List<String>>[
      [_formatMoney(previous), labels.previousBalance],
      [_formatMoney(totalSum), 'إجمالي ف.'],
      [_formatMoney(paid), labels.paid],
      [_formatMoney(totalSum - paid), 'المتبقي من الفاتورة'],
      [_formatMoney(balance), 'الرصيد الحالي (عليكم)'],
    ];

    final trailing = <String>[];
    if (settings.showTaxQrOnInvoice) {
      trailing.add(_center('QR الضريبة: #$invoiceNo', cols.width));
    }
    final notes = invoice['notes']?.toString() ?? '';
    if (notes.isNotEmpty) {
      trailing.add(_center('ملاحظات: $notes', cols.width));
    }

    return InvoiceReceiptPrintData(
      paperMm: settings.paperSize.widthMm,
      escFontSize: _escSizeFromFont(settings.fontSize),
      logoAssetPath: 'assets/Magdy store.png',
      centeredLines: centered,
      metaTableRows: metaTable,
      bodyLines: body,
      tableHeaders: const ['م', 'اسم المنتج', 'الكمية', 'السعر', 'الإجمالي'],
      tableRows: tableRows,
      qtyTotalLine: _center(_formatQty(qtySum), cols.width),
      summaryTableRows: summaryTable,
      trailingLines: trailing,
      salesFooter: InvoiceAppFooter.resolve(settings.salesInvoiceFooter),
    );
  }

  static int _escSizeFromFont(int fontSize) {
    if (fontSize >= 40) return 5;
    if (fontSize >= 35) return 4;
    if (fontSize >= 30) return 3;
    if (fontSize >= 25) return 2;
    return 1;
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

  /// Table row: long names wrap on full-width lines, then qty/price/total in columns.
  static void _writeProductRow(
    void Function(String text) line, {
    required _ReceiptColumns cols,
    required String rowNum,
    required String name,
    required String qty,
    required String price,
    required String total,
    required bool separateNameLine,
  }) {
    final needsWrap =
        separateNameLine || name.length > cols.product;
    if (needsWrap) {
      for (final wrapLine in _wrapProductName(name, cols.width)) {
        line(_fitLine(wrapLine, cols.width));
      }
      line(_tableRow(
        cols,
        rowNum: rowNum,
        total: total,
        price: price,
        qty: qty,
        product: '',
      ));
      return;
    }
    line(_tableRow(
      cols,
      rowNum: rowNum,
      total: total,
      price: price,
      qty: qty,
      product: _fitCell(name, cols.product),
    ));
  }

  static String _fitCell(String text, int width) {
    if (text.length <= width) return text;
    if (width <= 1) return text.substring(0, width);
    return text.substring(0, width - 1);
  }

  static String _fitLine(String text, int width) {
    if (text.length <= width) return text;
    return text.substring(0, width);
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
    _ReceiptColumns cols, {
    required String rowNum,
    required String product,
    required String qty,
    required String price,
    required String total,
  }) {
    return '${_col(total, cols.total, right: true)}|'
        '${_col(price, cols.price, right: true)}|'
        '${_col(qty, cols.qty, right: true)}|'
        '${_col(product, cols.product, center: true)}|'
        '${_col(rowNum, cols.rowNum, right: true)}';
  }

  static String _tableRule(_ReceiptColumns cols) {
    return '${'-' * cols.total}+'
        '${'-' * cols.price}+'
        '${'-' * cols.qty}+'
        '${'-' * cols.product}+'
        '${'-' * cols.rowNum}';
  }

  static String _col(String text, int width, {bool right = false, bool center = false}) {
    var t = text;
    if (t.length > width) t = t.substring(0, width);
    if (center) return _center(t, width);
    return right ? t.padLeft(width) : t.padRight(width);
  }

  static String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }
    final s = _money.format(value);
    if (s.endsWith('0') && s.contains('.')) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _formatMoneyCompact(double value) {
    if (value == value.roundToDouble()) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }
    return _money.format(value);
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
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
    buffer.writeln('-' * settings.paperSize.charsPerLine);
    buffer.writeln(InvoiceAppFooter.resolve(settings.salesInvoiceFooter));
    return buffer.toString().trimRight();
  }

  /// Sample invoice for preview / test print (6 items with long names).
  static Map<String, dynamic> sampleSalesInvoice() {
    return {
      'invoiceNumber': 1006,
      'date': DateTime(2024, 2, 26, 14, 49, 5),
      'clientName': 'عيد مطروح للتجارة والتوريدات',
      'paymentMethod': 'آجل',
      'previousBalance': 1250.0,
      'totalSum': 28025.0,
      'paidAmount': 5000.0,
      'balance': 24275.0,
      'notes': 'معاينة — أصناف بأسماء طويلة للاختبار',
      'products': [
        {
          'product':
              'ماسورة حديد مجلفن قطر 2 بوصة طول 6 متر مصنع حديد مصر درجة أولى',
          'amount': '12',
          'selectedPrice': 850.0,
          'total': 10200.0,
        },
        {
          'product':
              'علبة مسامير ستانلس 304 مقاس 8 ملم 50 قطعة للاستخدام الصناعي والورش',
          'amount': '5',
          'selectedPrice': 320.0,
          'total': 1600.0,
        },
        {
          'product':
              'صاج مجلفن أبيض سميك للأسقف والحوائط عرض 1.25 متر طول 3 متر',
          'amount': '20',
          'selectedPrice': 450.0,
          'total': 9000.0,
        },
        {
          'product':
              'بلف سلكة لحام كهربائي ألماني أصلي للمعدات الثقيلة والمصانع',
          'amount': '3',
          'selectedPrice': 1200.0,
          'total': 3600.0,
        },
        {
          'product':
              'عدد يدوي طرمبة مياه نحاس داخل وخارج للمنازل والمزارع ضمان سنة',
          'amount': '8',
          'selectedPrice': 275.0,
          'total': 2200.0,
        },
        {
          'product':
              'كوع بلاستيك بلد-sokta مواسير صرف صحي 160 ملم 90 درجة ضغط عالي',
          'amount': '15',
          'selectedPrice': 95.0,
          'total': 1425.0,
        },
      ],
    };
  }

  /// Sample sales invoice using current label/footer/toggle settings.
  static String buildSampleSalesInvoicePreview(PrinterSettings settings) {
    final body = format(
      invoice: sampleSalesInvoice(),
      settings: settings,
      context: const InvoicePrintContext(),
    );
    final footer = InvoiceAppFooter.resolve(settings.salesInvoiceFooter);
    return '$body${'-' * settings.paperSize.charsPerLine}\n$footer\n';
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
    buffer.writeln('── فاتورة مبيعات (6 أصناف — أسماء طويلة) ──');
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
