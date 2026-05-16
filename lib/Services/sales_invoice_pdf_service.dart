import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide TextDirection;
import 'package:pdf/widgets.dart' as pw;

class SalesInvoicePdfService {
  static Future<File> generate(Map<String, dynamic> invoice) async {
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

    final products =
        List<Map<String, dynamic>>.from(invoice['products'] ?? []);
    final totalSum = (invoice['totalSum'] as num?)?.toDouble() ?? 0.0;
    final paid = (invoice['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final balance = (invoice['balance'] as num?)?.toDouble() ?? 0.0;
    final discount = (invoice['invoiceDiscount'] as num?)?.toDouble() ?? 0.0;
    final previous =
        (invoice['previousBalance'] as num?)?.toDouble() ?? 0.0;

    String dateStr = '';
    final date = invoice['date'];
    if (date is Timestamp) {
      dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(date.toDate().toLocal());
    } else if (date is DateTime) {
      dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(date.toLocal());
    }

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

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(child: rtl('Kareem Store', bold: true, fontSize: 14)),
              pw.SizedBox(height: 6),
              pw.Center(child: rtl('فاتورة مبيعات', bold: true, fontSize: 16)),
              pw.SizedBox(height: 10),
              rtl('رقم الفاتورة: #${invoice['invoiceNumber']}'),
              rtl('العميل: ${invoice['clientName']}'),
              if (dateStr.isNotEmpty) rtl('التاريخ: $dateStr'),
              rtl('طريقة الدفع: ${invoice['paymentMethod']}'),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      h('المنتج'),
                      h('الكمية'),
                      h('السعر'),
                      h('الإجمالي'),
                    ],
                  ),
                  for (final p in products)
                    pw.TableRow(
                      children: [
                        d(p['product']?.toString() ?? ''),
                        d(p['amount']?.toString() ?? ''),
                        d(((p['selectedPrice'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2)),
                        d(((p['total'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2)),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),
              if (discount > 0)
                rtl('الخصم: ${discount.toStringAsFixed(2)}'),
              rtl('الرصيد السابق: ${previous.toStringAsFixed(2)}'),
              rtl('الإجمالي: ${totalSum.toStringAsFixed(2)}', bold: true),
              rtl('المدفوع: ${paid.toStringAsFixed(2)}'),
              rtl('المتبقي: ${balance.toStringAsFixed(2)}'),
              if ((invoice['notes']?.toString() ?? '').isNotEmpty)
                rtl('ملاحظات: ${invoice['notes']}'),
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
}
