import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'header_helper.dart';
import 'invoice_number_utils.dart';
import 'printer_settings_service.dart';

/// One row for the products list PDF (inventory or damaged).
class ProductListPdfRow {
  final int serial;
  final String name;
  final double costPrice;
  final double sellingPrice1;
  final double quantity;
  final String? subtitle;

  const ProductListPdfRow({
    required this.serial,
    required this.name,
    required this.costPrice,
    required this.sellingPrice1,
    required this.quantity,
    this.subtitle,
  });
}

class ProductsListPdfService {
  static String exportModeLabel({
    required bool includeCost,
    required bool includePrice,
  }) {
    final parts = <String>[];
    parts.add(includeCost ? 'مع التكلفة' : 'بدون التكلفة');
    parts.add(includePrice ? 'مع الأسعار' : 'بدون الأسعار');
    return parts.join(' • ');
  }

  static Future<File> generate({
    required List<ProductListPdfRow> rows,
    required String listTitle,
    required String filterLabel,
    required bool includeCost,
    required bool includePrice,
  }) async {
    final settings = await PrinterSettingsService.load();
    final amiriRegular = pw.Font.ttf(
      (await rootBundle.load('fonts/Amiri-Regular.ttf')).buffer.asByteData(),
    );
    final amiriBold = pw.Font.ttf(
      (await rootBundle.load('fonts/Amiri-Bold.ttf')).buffer.asByteData(),
    );

    pw.TextStyle cell({bool bold = false, double fontSize = 9}) =>
        pw.TextStyle(
          font: bold ? amiriBold : amiriRegular,
          fontSize: fontSize,
        );

    pw.Widget cellText(
      String text, {
      bool bold = false,
      double fontSize = 9,
    }) =>
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            text,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: cell(bold: bold, fontSize: fontSize),
          ),
        );

    final logoFile = HeaderHelper.getLogoFile(settings);
    final logoPdfImage = logoFile != null ? pw.MemoryImage(logoFile.readAsBytesSync()) : null;
    final headerLines = HeaderHelper.getHeaderLines(settings);
    final generatedAt =
        DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    final headers = <String>[
      'ت',
      'الإسم',
      if (includeCost) 'التكلفة',
      if (includePrice) 'سعر البيع',
      'الكمية',
    ];

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: headers.map((h) => cellText(h, bold: true)).toList(),
      ),
      for (final row in rows)
        pw.TableRow(
          children: [
            cellText('${row.serial}'),
            cellText(
              row.subtitle != null && row.subtitle!.isNotEmpty
                  ? '${row.name}\n${row.subtitle}'
                  : row.name,
              fontSize: 8,
            ),
            if (includeCost) cellText(invoiceAmount(row.costPrice)),
            if (includePrice) cellText(invoiceAmount(row.sellingPrice1)),
            cellText(invoiceQty(row.quantity)),
          ],
        ),
    ];

    final modeLabel = exportModeLabel(
      includeCost: includeCost,
      includePrice: includePrice,
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          if (logoPdfImage != null) ...[
            pw.Center(
              child: pw.Container(
                height: 50,
                child: pw.Image(logoPdfImage, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 6),
          ],
          for (final line in headerLines) ...[
            pw.Text(
              line,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: amiriBold,
                fontSize: 14,
              ),
            ),
            pw.SizedBox(height: 2),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            listTitle,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: amiriBold, fontSize: 14),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'التصفية: $filterLabel • $modeLabel',
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: cell(fontSize: 10),
          ),
          pw.Text(
            'تاريخ التصدير: $generatedAt • عدد المنتجات: ${rows.length}',
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: cell(fontSize: 9),
          ),
          pw.SizedBox(height: 14),
          if (rows.isEmpty)
            pw.Text(
              'لا توجد منتجات للعرض',
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: cell(fontSize: 11),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: tableRows,
            ),
        ],
      ),
    );

    final safeFilter = filterLabel.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final costTag = includeCost ? 'تكلفة' : 'لا_تكلفة';
    final priceTag = includePrice ? 'اسعار' : 'لا_اسعار';
    final fileName =
        'منتجات_${safeFilter}_${costTag}_${priceTag}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
