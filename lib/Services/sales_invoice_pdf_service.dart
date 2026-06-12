import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice_app_footer.dart';
import 'invoice_number_utils.dart';
import 'printer_settings_service.dart';

class SalesInvoicePdfService {
  static Future<File> generate(Map<String, dynamic> rawInvoice) async {
    final invoice = invoiceForPdfExport(rawInvoice);
    final settings = await PrinterSettingsService.load();
    final amiriRegular =
        pw.Font.ttf((await rootBundle.load('fonts/Amiri-Regular.ttf'))
            .buffer
            .asByteData());
    final amiriBold = pw.Font.ttf(
        (await rootBundle.load('fonts/Amiri-Bold.ttf')).buffer.asByteData());

    pw.TextStyle cell({bool bold = false, double fontSize = 10}) =>
        pw.TextStyle(
          font: bold ? amiriBold : amiriRegular,
          fontSize: fontSize,
        );

    pw.Widget rtl(String text, {bool bold = false, double fontSize = 10}) =>
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.right,
          style: cell(bold: bold, fontSize: fontSize),
        );

    pw.Widget center(String text, {bool bold = false, double fontSize = 11}) =>
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: cell(bold: bold, fontSize: fontSize),
        );

    final products =
        List<Map<String, dynamic>>.from(invoice['products'] ?? []);
    final totalSum = (invoice['totalSum'] as num?)?.toDouble() ?? 0.0;
    final paid = (invoice['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final previous =
        (invoice['previousBalance'] as num?)?.toDouble() ?? 0.0;
    final balance = invoiceClientRemainingOwed(invoice);
    final when = _parseDateTime(invoice['date']);
    final typeLabel = _paymentTypeLabel(invoice['paymentMethod']);
    final qtySum = products.fold<double>(
      0,
      (s, p) => s + _num(p['amount']),
    );

    pw.Widget h(String t) => pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(t,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: true, fontSize: 9)),
        );

    pw.Widget d(String t) => pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(t,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(fontSize: 9)),
        );

    final headerLines = <String>[
      if (settings.receiptStoreName.trim().isNotEmpty)
        settings.receiptStoreName.trim(),
      if (settings.receiptStoreAddress.trim().isNotEmpty)
        settings.receiptStoreAddress.trim(),
      if (settings.receiptStorePhone.trim().isNotEmpty)
        settings.receiptStorePhone.trim(),
    ];
    if (headerLines.isEmpty) {
      headerLines.add('أبو مجدي للحدايد والعدد والديكور والخشب والحلايا');
      headerLines.add('كفر الزيات - طنطا - الغربية');
      headerLines.add('01010573888');
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (final line in headerLines) ...[
                center(line, bold: true, fontSize: 13),
                pw.SizedBox(height: 2),
              ],
              center(settings.labels.invoiceTitle, bold: true, fontSize: 16),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  rtl('النوع : $typeLabel', fontSize: 10),
                  rtl('الرقم : ${invoice['invoiceNumber']}', fontSize: 10),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  rtl('التاريخ : ${when.date}', fontSize: 10),
                  rtl('الوقت : ${when.time}', fontSize: 10),
                ],
              ),
              pw.Divider(),
              center(
                'اسم العميل : ${invoice['clientName']?.toString() ?? ''}',
                fontSize: 12,
                bold: true,
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(1.2),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      h('اسم المنتج'),
                      h('الكمية'),
                      h('السعر'),
                      h('الإجمالي'),
                    ],
                  ),
                  for (final p in products)
                    pw.TableRow(
                      children: [
                        d(invoiceProductName(p)),
                        d(p['amount']?.toString() ?? ''),
                        d(invoiceAmount(p['selectedPrice'])),
                        d(invoiceAmount(p['total'])),
                      ],
                    ),
                  pw.TableRow(
                    children: [
                      d(''),
                      d(invoiceQty(qtySum)),
                      d(''),
                      d(''),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              rtl(
                  '${settings.labels.previousBalance} : ${invoiceAmount(previous)}'),
              rtl('إجمالي ف. : ${invoiceAmount(totalSum)}', bold: true),
              rtl('${settings.labels.paid} : ${invoiceAmount(paid)}'),
              rtl('الرصيد الحالي (عليكم) : ${invoiceAmount(balance)}',
                  bold: true),
              if ((invoice['notes']?.toString() ?? '').isNotEmpty)
                rtl('ملاحظات: ${invoice['notes']}'),
              pw.SizedBox(height: 10),
              for (final line
                  in InvoiceAppFooter.resolveLines(settings.salesInvoiceFooter))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Center(child: center(line, fontSize: 9)),
                ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final invoiceNo = invoice['invoiceNumber']?.toString() ?? '0';
    final file = File('${dir.path}/فاتورة_$invoiceNo.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
    if (dt == null) return const _InvoiceWhen(date: '', time: '');
    final d = dt;
    return _InvoiceWhen(
      date:
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}',
      time:
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}',
    );
  }
}

class _InvoiceWhen {
  final String date;
  final String time;

  const _InvoiceWhen({required this.date, required this.time});
}
