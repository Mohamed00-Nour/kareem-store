import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide TextDirection;
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice_app_footer.dart';
import 'invoice_number_utils.dart';
import 'printer_settings_service.dart';

enum ClientStatementType { financial, invoices, returns }

class ClientStatementPdfService {
  static Future<File> generate({
    required String clientId,
    required ClientStatementType type,
    required DateTime from,
    required DateTime to,
  }) async {
    final endInclusive = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final startInclusive = DateTime(from.year, from.month, from.day);

    final clientDoc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .get();
    final clientName =
        (clientDoc.data()?['clientName'] ?? clientId).toString();

    final amiriRegular = pw.Font.ttf(
        (await rootBundle.load('fonts/Amiri-Regular.ttf')).buffer.asByteData());
    final amiriBold = pw.Font.ttf(
        (await rootBundle.load('fonts/Amiri-Bold.ttf')).buffer.asByteData());
    final tajawalFont = pw.Font.ttf(
        (await rootBundle.load('fonts/Tajawal-Medium.ttf')).buffer.asByteData());

    pw.TextStyle cell({bool bold = false, double fontSize = 10, bool useTajawal = false}) =>
        pw.TextStyle(
          font: useTajawal ? tajawalFont : (bold ? amiriBold : amiriRegular),
          fontSize: fontSize,
        );

    pw.Widget rtl(String text, {bool bold = false, double fontSize = 10, bool useTajawal = false}) =>
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.right,
          style: cell(bold: bold, fontSize: fontSize, useTajawal: useTajawal),
        );

    final periodStr =
        'من ${DateFormat('dd/MM/yyyy').format(startInclusive)} إلى ${DateFormat('dd/MM/yyyy').format(endInclusive)}';
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    final settings = await PrinterSettingsService.load();
    final invoiceFooter = settings.salesInvoiceFooter;
    final reportFooter = settings.a4ReportFooter;

    pw.Widget center(String text, {bool bold = false, double fontSize = 10, bool useTajawal = false}) =>
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: cell(bold: bold, fontSize: fontSize, useTajawal: useTajawal),
        );

    final pdf = pw.Document();

    switch (type) {
      case ClientStatementType.financial:
        final clientBalance = clientDoc.exists
            ? (clientDoc.data()?['balance'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        await _addFinancialPages(
          pdf: pdf,
          clientId: clientId,
          clientName: clientName,
          clientBalance: clientBalance,
          start: startInclusive,
          end: endInclusive,
          periodStr: periodStr,
          nowStr: nowStr,
          cell: cell,
          rtl: rtl,
          center: center,
          reportFooter: reportFooter,
        );
        break;
      case ClientStatementType.invoices:
        await _addInvoicePages(
          pdf: pdf,
          clientId: clientId,
          clientName: clientName,
          start: startInclusive,
          end: endInclusive,
          periodStr: periodStr,
          nowStr: nowStr,
          cell: cell,
          rtl: rtl,
          center: center,
          invoiceFooter: invoiceFooter,
          invoicesSubcollection: 'invoices',
          statementHeader: 'كشف حساب الفواتير',
          invoiceTypeLabel: 'فاتورة مبيعات',
          emptyMessage: 'لا توجد فواتير في هذه الفترة',
        );
        break;
      case ClientStatementType.returns:
        await _addInvoicePages(
          pdf: pdf,
          clientId: clientId,
          clientName: clientName,
          start: startInclusive,
          end: endInclusive,
          periodStr: periodStr,
          nowStr: nowStr,
          cell: cell,
          rtl: rtl,
          center: center,
          invoiceFooter: invoiceFooter,
          invoicesSubcollection: 'returnInvoices',
          statementHeader: 'كشف حساب فواتير المرتجع',
          invoiceTypeLabel: 'فاتورة مرتجع',
          emptyMessage: 'لا توجد فواتير مرتجع في هذه الفترة',
        );
        break;
    }

    final dir = await getTemporaryDirectory();
    final safeName = clientName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    String typeLabel;
    if (type == ClientStatementType.financial) {
      typeLabel = 'مالي';
    } else if (type == ClientStatementType.returns) {
      typeLabel = 'مرتجع';
    } else {
      typeLabel = 'فواتير';
    }
    final fileName =
        'كشف_حساب_${typeLabel}_${safeName}_${DateFormat('yyyyMMdd').format(startInclusive)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> _addFinancialPages({
    required pw.Document pdf,
    required String clientId,
    required String clientName,
    required double clientBalance,
    required DateTime start,
    required DateTime end,
    required String periodStr,
    required String nowStr,
    required String reportFooter,
    required pw.TextStyle Function({bool bold, double fontSize, bool useTajawal}) cell,
    required pw.Widget Function(String text, {bool bold, double fontSize, bool useTajawal}) rtl,
    required pw.Widget Function(String text, {bool bold, double fontSize, bool useTajawal}) center,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('balanceHistory')
        .orderBy('timestamp', descending: true)
        .get();

    final payments = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final entered = (data['enteredBalance'] as num?)?.toDouble() ?? 0.0;
      final before = (data['balanceBefore'] as num?)?.toDouble() ?? 0.0;

      final type = data['type']?.toString() ?? 'deduction';
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
      final notes = (data['notes'] ?? data['description'] ?? '').toString().trim();

      String description = '';
      if (type == 'sale') {
        description = invoiceNumber.isNotEmpty ? 'فاتورة مبيعات رقم $invoiceNumber' : 'فاتورة مبيعات';
      } else if (type == 'sale_payment') {
        description = invoiceNumber.isNotEmpty ? 'سداد من فاتورة رقم $invoiceNumber' : 'سداد فاتورة';
      } else if (type == 'return') {
        description = invoiceNumber.isNotEmpty ? 'مرتجع مبيعات رقم $invoiceNumber' : 'مرتجع مبيعات';
      } else if (type == 'return_payment') {
        description = invoiceNumber.isNotEmpty ? 'سداد مرتجع رقم $invoiceNumber' : 'سداد مرتجع';
      } else if (type == 'opening') {
        description = 'رصيد افتتاحي';
      } else if (type == 'addition') {
        description = 'إضافة رصيد';
      } else {
        description = 'خصم رصيد (سداد)';
      }
      if (notes.isNotEmpty) {
        description += ' ($notes)';
      }

      final isIncrease = type == 'sale' || type == 'addition' || type == 'opening' || type == 'return_payment';
      final after = isIncrease ? before + entered : before - entered;
      final sign = isIncrease ? '+' : '-';

      payments.add({
        'date': date,
        'entered': entered,
        'before': before,
        'after': after,
        'description': description,
        'sign': sign,
        'type': type,
        'invoiceId': data['invoiceId']?.toString() ?? '',
        'timestamp': ts,
      });
    }

    int typePriority(String t) {
      switch (t) {
        case 'opening':
          return 7;
        case 'sale_payment':
          return 1;
        case 'sale':
          return 2;
        case 'return_payment':
          return 3;
        case 'return':
          return 4;
        case 'addition':
          return 5;
        case 'deduction':
          return 6;
        default:
          return 8;
      }
    }

    payments.sort((a, b) {
      final typeA = a['type']?.toString() ?? '';
      final typeB = b['type']?.toString() ?? '';

      // Opening always last (oldest) in a descending list
      if (typeA == 'opening' && typeB != 'opening') return 1;
      if (typeB == 'opening' && typeA != 'opening') return -1;

      // Group by same invoiceId
      final invA = a['invoiceId']?.toString() ?? '';
      final invB = b['invoiceId']?.toString() ?? '';
      if (invA.isNotEmpty && invA == invB) {
        return typePriority(typeA).compareTo(typePriority(typeB));
      }

      // Then by timestamp descending (newest first)
      final tsA = a['timestamp'];
      final tsB = b['timestamp'];
      DateTime? dateA, dateB;
      if (tsA is Timestamp) dateA = tsA.toDate();
      if (tsB is Timestamp) dateB = tsB.toDate();

      if (dateA != null && dateB != null) {
        final cmp = dateB.compareTo(dateA); // Descending!
        if (cmp != 0) return cmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      return typePriority(typeA).compareTo(typePriority(typeB));
    });

    pw.Widget headerCell(String t) => pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(t,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: true, fontSize: 9)),
        );

    pw.Widget dataCell(String t, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(t,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(bold: bold, fontSize: 9, useTajawal: true)),
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: rtl('أبو مجدي للحدايد والعدد', bold: true, fontSize: 14),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: rtl('كشف حساب مالي', bold: true, fontSize: 16),
              ),
              pw.SizedBox(height: 6),
              pw.Center(child: rtl('العميل: $clientName', fontSize: 12)),
              pw.SizedBox(height: 4),
              pw.Center(child: rtl(periodStr, fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('تاريخ التقرير: $nowStr', textDirection: pw.TextDirection.rtl, style: cell(fontSize: 8, useTajawal: true)),
              ),
              pw.SizedBox(height: 16),
              if (payments.isEmpty)
                pw.Center(
                  child: rtl('لا توجد دفعات في هذه الفترة', fontSize: 12),
                )
              else
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.5),
                    1: const pw.FlexColumnWidth(3.0),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('التاريخ'),
                        headerCell('البيان'),
                        headerCell('المبلغ'),
                        headerCell('الرصيد قبل'),
                        headerCell('الرصيد بعد'),
                      ],
                    ),
                    for (final p in payments)
                      pw.TableRow(
                        children: [
                          dataCell(DateFormat('dd/MM/yyyy')
                              .format(p['date'] as DateTime)),
                          dataCell(p['description'] as String),
                          dataCell('${p['sign']}${(p['entered'] as double).toStringAsFixed(2)}'),
                          dataCell((p['before'] as double).toStringAsFixed(2)),
                          dataCell((p['after'] as double).toStringAsFixed(2)),
                        ],
                      ),
                  ],
                ),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey400, width: 1),
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    rtl(invoiceAmount(clientBalance), bold: true, fontSize: 11),
                    rtl('الرصيد الحالي عليكم:', bold: true, fontSize: 11),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              for (final line in InvoiceAppFooter.resolveLines(reportFooter))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Center(child: center(line, fontSize: 9)),
                ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _addInvoicePages({
    required pw.Document pdf,
    required String clientId,
    required String clientName,
    required DateTime start,
    required DateTime end,
    required String periodStr,
    required String nowStr,
    required String invoiceFooter,
    required pw.TextStyle Function({bool bold, double fontSize, bool useTajawal}) cell,
    required pw.Widget Function(String text, {bool bold, double fontSize, bool useTajawal}) rtl,
    required pw.Widget Function(String text, {bool bold, double fontSize, bool useTajawal}) center,
    required String invoicesSubcollection,
    required String statementHeader,
    required String invoiceTypeLabel,
    required String emptyMessage,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection(invoicesSubcollection)
        .orderBy('date', descending: true)
        .get();

    final invoices = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final date = doc.data()['date'];
      if (date is! Timestamp) continue;
      final d = date.toDate();
      if (d.isBefore(start) || d.isAfter(end)) continue;
      invoices.add(doc);
    }

    if (invoices.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            children: [
              pw.Center(child: rtl(statementHeader, bold: true, fontSize: 16)),
              pw.SizedBox(height: 8),
              pw.Center(child: rtl('العميل: $clientName')),
              pw.SizedBox(height: 8),
              pw.Center(child: rtl(periodStr)),
              pw.SizedBox(height: 16),
              pw.Center(child: rtl(emptyMessage)),
            ],
          ),
        ),
      );
      return;
    }

    for (final doc in invoices) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final date = (data['date'] as Timestamp).toDate();
      final products =
          List<Map<String, dynamic>>.from(data['products'] ?? []);
      final totalSum =
          (data['totalSum'] as num?)?.toDouble() ?? 0.0;
      final paid =
          (data['paidAmount'] as num?)?.toDouble() ?? 0.0;
      final previous =
          (data['previousBalance'] as num?)?.toDouble() ?? 0.0;
      final remaining = invoiceClientRemainingOwed(data);
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '-';

      pw.Widget h(String t) => pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(t,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(bold: true, fontSize: 8)),
          );

      pw.Widget d(String t) => pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(t,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(fontSize: 8)),
          );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                    child: rtl('أبو مجدي للحدايد والعدد', bold: true, fontSize: 12)),
                pw.SizedBox(height: 6),
                pw.Center(
                    child: rtl(statementHeader, bold: true, fontSize: 14)),
                pw.SizedBox(height: 4),
                pw.Center(child: rtl('العميل: $clientName', fontSize: 11)),
                pw.SizedBox(height: 2),
                pw.Center(child: rtl(periodStr, fontSize: 9)),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 6),
                rtl('$invoiceTypeLabel #$invoiceNumber',
                    bold: true, fontSize: 12),
                pw.SizedBox(height: 4),
                rtl('التاريخ: ${DateFormat('dd/MM/yyyy hh:mm a').format(date)}',
                    fontSize: 10),
                pw.SizedBox(height: 10),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
                          d(invoiceProductName(p)),
                          d(p['amount']?.toString() ?? ''),
                          d(invoiceAmount(p['selectedPrice'])),
                          d(invoiceAmount(p['total'])),
                        ],
                      ),
                  ],
                ),
                pw.SizedBox(height: 12),
                rtl('الرصيد السابق: ${invoiceAmount(previous)}'),
                rtl('إجمالي الفاتورة: ${invoiceAmount(totalSum)}',
                    bold: true),
                rtl('المدفوع: ${invoiceAmount(paid)}'),
                rtl('المتبقي من الفاتورة: ${invoiceAmount(totalSum - paid)}'),
                rtl('المتبقي عليكم: ${invoiceAmount(remaining)}'),
                if ((data['notes']?.toString() ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  rtl('ملاحظات: ${data['notes']}'),
                ],
                pw.SizedBox(height: 10),
                for (final line in InvoiceAppFooter.resolveLines(invoiceFooter))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Center(child: center(line, fontSize: 9)),
                  ),
                pw.Spacer(),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text('صفحة فاتورة',
                      style: cell(fontSize: 8, bold: false)),
                ),
              ],
            );
          },
        ),
      );
    }
  }
}
