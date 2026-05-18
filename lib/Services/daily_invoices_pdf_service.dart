import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide TextDirection;
import 'package:pdf/widgets.dart' as pw;

/// Builds a PDF with one sales invoice per page.
class DailyInvoicesPdfService {
  static Future<File> generate({
    required List<Map<String, dynamic>> invoices,
    required DateTime from,
    required DateTime to,
  }) async {
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

    final periodStr =
        'من ${DateFormat('dd/MM/yyyy').format(from)} إلى ${DateFormat('dd/MM/yyyy').format(to)}';
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    final pdf = pw.Document();

    if (invoices.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            children: [
              pw.Center(child: rtl('تقرير فواتير المبيعات', bold: true, fontSize: 16)),
              pw.SizedBox(height: 8),
              pw.Center(child: rtl(periodStr)),
              pw.SizedBox(height: 16),
              pw.Center(child: rtl('لا توجد فواتير في هذه الفترة')),
            ],
          ),
        ),
      );
    } else {
      for (final data in invoices) {
        _addInvoicePage(
          pdf: pdf,
          data: data,
          periodStr: periodStr,
          nowStr: nowStr,
          cell: cell,
          rtl: rtl,
        );
      }
    }

    final dir = await getTemporaryDirectory();
    final fileName =
        'فواتير_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static void _addInvoicePage({
    required pw.Document pdf,
    required Map<String, dynamic> data,
    required String periodStr,
    required String nowStr,
    required pw.TextStyle Function({bool bold, double fontSize}) cell,
    required pw.Widget Function(String text, {bool bold, double fontSize}) rtl,
  }) {
    final date = _parseDate(data['date']);
    final products = List<Map<String, dynamic>>.from(data['products'] ?? []);
    final totalSum = _num(data['totalSum']);
    final paid = _num(data['paidAmount']);
    final previous = _num(data['previousBalance']);
    final balance = _num(data['balance']);
    final profit = _num(data['profitMargin']);
    final invoiceNumber = data['invoiceNumber']?.toString() ?? '-';
    final clientName = data['clientName']?.toString() ?? '';

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

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(child: rtl('Kareem Store', bold: true, fontSize: 14)),
              pw.SizedBox(height: 6),
              pw.Center(child: rtl('فاتورة مبيعات', bold: true, fontSize: 16)),
              pw.SizedBox(height: 4),
              pw.Center(child: rtl(periodStr, fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),
              rtl('رقم الفاتورة: #$invoiceNumber', bold: true, fontSize: 12),
              rtl('العميل: $clientName', fontSize: 11),
              if (date != null)
                rtl('التاريخ: ${DateFormat('dd/MM/yyyy hh:mm a').format(date)}',
                    fontSize: 10),
              if ((data['paymentMethod']?.toString() ?? '').isNotEmpty)
                rtl('طريقة الدفع: ${data['paymentMethod']}', fontSize: 10),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.2),
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
                        d(_num(p['selectedPrice']).toStringAsFixed(2)),
                        d(_num(p['total']).toStringAsFixed(2)),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),
              if (previous != 0) rtl('الرصيد السابق: ${previous.toStringAsFixed(2)}'),
              rtl('إجمالي الفاتورة: ${totalSum.toStringAsFixed(2)} ج.م',
                  bold: true),
              rtl('المدفوع: ${paid.toStringAsFixed(2)} ج.م'),
              rtl('المتبقي: ${balance.toStringAsFixed(2)} ج.م'),
              if (profit != 0)
                rtl('هامش الربح: ${profit.toStringAsFixed(2)} ج.م', fontSize: 9),
              if ((data['notes']?.toString() ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 6),
                rtl('ملاحظات: ${data['notes']}'),
              ],
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(nowStr, style: cell(fontSize: 8)),
                  pw.Text('صفحة فاتورة', style: cell(fontSize: 8)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is Timestamp) return date.toDate().toLocal();
    if (date is DateTime) return date.toLocal();
    return null;
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
