import 'package:cloud_firestore/cloud_firestore.dart';

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

class InvoicePrintFormatter {
  static String format({
    required Map<String, dynamic> invoice,
    required PrinterSettings settings,
    InvoicePrintContext context = const InvoicePrintContext(),
  }) {
    final labels = settings.labels;
    final pad = settings.rightMargin > 0 ? ' ' * settings.rightMargin : '';
    final separator = '-' * settings.paperSize.charsPerLine;
    final buffer = StringBuffer();

    void line(String text) => buffer.writeln('$pad$text');

    line('Kareem Store');
    line(labels.invoiceTitle);
    line(separator);
    line('${labels.invoiceNumber}: #${invoice['invoiceNumber']}');

    final dateStr = _formatInvoiceDate(invoice['date']);
    if (dateStr.isNotEmpty) {
      line('${labels.date}: $dateStr');
    }

    line('${labels.client}: ${invoice['clientName'] ?? ''}');

    if (settings.showCustomerAddressAndPhone) {
      final address = context.clientAddress?.trim() ?? '';
      final phone = context.clientPhone?.trim() ?? '';
      if (address.isNotEmpty) {
        line('${labels.address}: $address');
      }
      if (phone.isNotEmpty) {
        line('${labels.phone}: $phone');
      }
    }

    if (settings.showPreviousCustomerDebt) {
      final prev = invoice['previousBalance'];
      if (prev != null) {
        line(
            '${labels.previousBalance}: ${_num(prev).toStringAsFixed(2)}');
      }
    }

    line(separator);

    final products = invoice['products'] as List<dynamic>? ?? [];
    for (final item in products) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = map['product']?.toString() ?? '';
      final qty = map['amount']?.toString() ?? '';
      final price = _num(map['selectedPrice']).toStringAsFixed(2);
      final total = _num(map['total']).toStringAsFixed(2);
      final details = context.productDetailsByName[name] ?? {};

      if (settings.printProductNameOnSeparateLine) {
        line(name);
        line(
            '${labels.quantity}: $qty  ${labels.price}: $price  ${labels.lineTotal}: $total');
      } else {
        line('$name  x$qty  $price  = $total');
      }

      if (settings.showProductDescription) {
        final desc = map['description']?.toString() ??
            details['description']?.toString() ??
            '';
        if (desc.isNotEmpty) {
          line('${labels.description}: $desc');
        }
      }

      if (settings.showProductNumberOnA4) {
        final num = map['randomNumber']?.toString() ??
            details['randomNumber']?.toString() ??
            '';
        if (num.isNotEmpty) {
          line('${labels.productNumber}: $num');
        }
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
          line('${labels.expiryDate}: $expiryStr');
        }
      }

      if (settings.showProductImageOnInvoice) {
        final image = map['image']?.toString() ??
            details['image']?.toString() ??
            '';
        if (image.isNotEmpty) {
          line('[${labels.product} صورة]');
        }
      }
    }

    line(separator);
    line('${labels.total}: ${_num(invoice['totalSum']).toStringAsFixed(2)}');
    line('${labels.paid}: ${_num(invoice['paidAmount']).toStringAsFixed(2)}');
    line('${labels.balance}: ${_num(invoice['balance']).toStringAsFixed(2)}');

    if (settings.showTaxQrOnInvoice) {
      line('QR الضريبة: #${invoice['invoiceNumber']}');
    }

    final notes = invoice['notes']?.toString() ?? '';
    if (notes.isNotEmpty) {
      line('ملاحظات: $notes');
    }

    return buffer.toString();
  }

  /// Plain-text test slip (matches [BluetoothPrinterService.printTestReceipt]).
  static String buildPrinterTestPreview(PrinterSettings settings) {
    final buffer = StringBuffer();
    buffer.writeln('Kareem Store');
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
      'invoiceNumber': 1001,
      'date': DateTime.now().toIso8601String(),
      'clientName': 'عميل تجريبي',
      'previousBalance': 150.0,
      'totalSum': 250.0,
      'paidAmount': 200.0,
      'balance': 50.0,
      'notes': 'معاينة — لا حاجة لطابعة',
      'products': [
        {
          'product': 'سكر 1 كجم',
          'amount': '2',
          'selectedPrice': 50.0,
          'total': 100.0,
          'description': 'وصف تجريبي',
        },
        {
          'product': 'زيت عباد الشمس',
          'amount': '1',
          'selectedPrice': 150.0,
          'total': 150.0,
        },
      ],
    };
  }

  /// Sample sales invoice using current label/footer/toggle settings.
  static String buildSampleSalesInvoicePreview(PrinterSettings settings) {
    final body = format(
      invoice: _sampleSalesInvoice(),
      settings: settings,
      context: const InvoicePrintContext(
        clientAddress: 'القاهرة — معاينة',
        clientPhone: '01000000000',
        productDetailsByName: {
          'سكر 1 كجم': {'randomNumber': 'A-001'},
        },
      ),
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

  static String _formatInvoiceDate(dynamic date) {
    if (date == null) return '';
    try {
      if (date is Timestamp) {
        return date.toDate().toLocal().toString().split(' ')[0];
      }
      if (date is DateTime) {
        return date.toLocal().toString().split(' ')[0];
      }
    } catch (_) {}
    final text = date.toString();
    if (text.length >= 10) return text.substring(0, 10);
    return text;
  }
}
