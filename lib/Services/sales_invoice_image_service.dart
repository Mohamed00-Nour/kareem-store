import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

import '../Widgets/invoice_receipt_card.dart';
import '../models/printer_settings.dart';
import 'invoice_number_utils.dart';
import 'printer_settings_service.dart';

class SalesInvoiceImageService {
  /// Conservative limit so PNG capture does not clip rows or footer text.
  static const int maxProductsPerPage = 12;
  static const double _captureBottomPadding = 48;

  static double _qtySum(List<Map<String, dynamic>> products) {
    return products.fold<double>(
      0,
      (s, p) => s + invoiceNum(p['amount']),
    );
  }

  /// One or more PNG files when the invoice has many product lines.
  static Future<List<File>> generatePngPages(
    Map<String, dynamic> invoice,
  ) async {
    final allProducts =
        List<Map<String, dynamic>>.from(invoice['products'] ?? []);
    final settings = await PrinterSettingsService.load();
    final number = invoice['invoiceNumber']?.toString() ?? 'invoice';
    final dir = await getTemporaryDirectory();
    final fullQtySum = _qtySum(allProducts);

    if (allProducts.length <= maxProductsPerPage) {
      final file = await _capturePage(
        invoice: invoice,
        products: allProducts,
        settings: settings,
        outputPath: '${dir.path}/invoice_$number.png',
        showStoreHeader: true,
        showClientAndMeta: true,
        showSummary: true,
        showFooter: true,
        showQtyTotalRow: true,
        showNotes: true,
        qtySumOverride: fullQtySum,
        captureBottomPadding: 24,
      );
      return [file];
    }

    final pageCount = (allProducts.length / maxProductsPerPage).ceil();
    final files = <File>[];

    for (var page = 0; page < pageCount; page++) {
      final start = page * maxProductsPerPage;
      final end = (start + maxProductsPerPage).clamp(0, allProducts.length);
      final chunk = allProducts.sublist(start, end);
      final isFirst = page == 0;
      final isLast = page == pageCount - 1;

      files.add(
        await _capturePage(
          invoice: invoice,
          products: chunk,
          settings: settings,
          outputPath: '${dir.path}/invoice_${number}_p${page + 1}.png',
          showStoreHeader: isFirst,
          showClientAndMeta: isFirst,
          showCompactHeader: !isFirst,
          showSummary: isLast,
          showFooter: isLast,
          showQtyTotalRow: isLast,
          showNotes: isLast,
          qtySumOverride: isLast ? fullQtySum : null,
          pageIndicator: 'الصفحة ${page + 1} من $pageCount',
          leadingContinuationBanner: page > 0
              ? 'تابع المنتجات\n(من الصورة السابقة)'
              : null,
          productIndexOffset: start,
          captureBottomPadding: _captureBottomPadding,
          useLowerPixelRatio: true,
        ),
      );
    }

    return files;
  }

  static Future<File> generatePng(Map<String, dynamic> invoice) async {
    final pages = await generatePngPages(invoice);
    return pages.first;
  }

  static Future<File> _capturePage({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> products,
    required PrinterSettings settings,
    required String outputPath,
    required bool showStoreHeader,
    required bool showClientAndMeta,
    bool showCompactHeader = false,
    required bool showSummary,
    required bool showFooter,
    required bool showQtyTotalRow,
    required bool showNotes,
    double? qtySumOverride,
    String? pageIndicator,
    String? leadingContinuationBanner,
    int productIndexOffset = 0,
    double captureBottomPadding = 0,
    bool useLowerPixelRatio = false,
  }) async {
    final controller = ScreenshotController();
    final pixelRatio = useLowerPixelRatio ? 2.0 : 2.5;
    final bytes = await controller.captureFromWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Colors.white,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: InvoiceReceiptCard(
                invoice: invoice,
                products: products,
                storeName: settings.receiptStoreName,
                storeAddress: settings.receiptStoreAddress,
                storePhone: settings.receiptStorePhone,
                logoPath: settings.receiptLogoPath,
                showStoreHeader: showStoreHeader,
                showClientAndMeta: showClientAndMeta,
                showCompactHeader: showCompactHeader,
                showSummary: showSummary,
                showFooter: showFooter,
                showQtyTotalRow: showQtyTotalRow,
                showNotes: showNotes,
                qtySumOverride: qtySumOverride,
                pageIndicator: pageIndicator,
                leadingContinuationBanner: leadingContinuationBanner,
                captureBottomPadding: captureBottomPadding,
                productIndexOffset: productIndexOffset,
              ),
            ),
          ),
        ),
      ),
      pixelRatio: pixelRatio,
      delay: const Duration(milliseconds: 200),
    );

    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    return file;
  }
}
