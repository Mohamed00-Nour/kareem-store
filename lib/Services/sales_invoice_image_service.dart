import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

import '../Widgets/invoice_receipt_card.dart';
import 'printer_settings_service.dart';

class SalesInvoiceImageService {
  static Future<File> generatePng(Map<String, dynamic> invoice) async {
    final settings = await PrinterSettingsService.load();
    final controller = ScreenshotController();
    final bytes = await controller.captureFromWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Colors.white,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: InvoiceReceiptCard(
              invoice: invoice,
              storeName: settings.receiptStoreName,
              storeAddress: settings.receiptStoreAddress,
              storePhone: settings.receiptStorePhone,
            ),
          ),
        ),
      ),
      pixelRatio: 2.5,
      delay: const Duration(milliseconds: 80),
    );

    final dir = await getTemporaryDirectory();
    final number = invoice['invoiceNumber']?.toString() ?? 'invoice';
    final file = File('${dir.path}/invoice_$number.png');
    await file.writeAsBytes(bytes);
    return file;
  }
}
