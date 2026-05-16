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
    final buffer = StringBuffer();

    void line(String text) => buffer.writeln('$pad$text');

    line('Kareem Store');
    line(labels.invoiceTitle);
    line('------------------------------');
    line('${labels.invoiceNumber}: #${invoice['invoiceNumber']}');

    final date = invoice['date'];
    String dateStr = '';
    if (date != null) {
      try {
        dateStr = date.toDate().toLocal().toString().split(' ')[0];
      } catch (_) {
        dateStr = date.toString();
      }
    }
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

    line('------------------------------');

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

    line('------------------------------');
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

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
