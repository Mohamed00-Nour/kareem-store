import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/printer_settings.dart';
import 'bluetooth_printer_service.dart';
import 'invoice_print_formatter.dart';
import 'printer_settings_service.dart';

class InvoicePrintService {
  static Future<bool> printSalesInvoice(
    Map<String, dynamic> invoice,
  ) async {
    final settings = await PrinterSettingsService.load();
    if (!settings.printImmediatelyAfterSave &&
        settings.connectionType != PrinterConnectionType.bluetooth) {
      // Allow manual print even when auto-print is off.
    }
    if (settings.connectionType != PrinterConnectionType.bluetooth) {
      return false;
    }
    if (settings.bluetoothMacAddress.isEmpty) {
      return false;
    }

    final context = await _buildContext(invoice, settings);
    return BluetoothPrinterService.printSalesInvoice(
      invoice: invoice,
      settings: settings,
      context: context,
    );
  }

  static Future<bool> tryAutoPrintAfterSave(
    Map<String, dynamic> invoice,
  ) async {
    final settings = await PrinterSettingsService.load();
    if (!settings.printImmediatelyAfterSave) return false;
    if (settings.connectionType != PrinterConnectionType.bluetooth) {
      return false;
    }
    if (settings.bluetoothMacAddress.isEmpty) return false;

    final context = await _buildContext(invoice, settings);
    return BluetoothPrinterService.printSalesInvoice(
      invoice: invoice,
      settings: settings,
      context: context,
    );
  }

  static Future<InvoicePrintContext> _buildContext(
    Map<String, dynamic> invoice,
    PrinterSettings settings,
  ) async {
    String? address;
    String? phone;
    final clientName = invoice['clientName']?.toString() ?? '';

    if (settings.showCustomerAddressAndPhone && clientName.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientName)
          .get();
      if (snap.exists) {
        final data = snap.data();
        address = data?['address']?.toString() ?? data?['clientAddress']?.toString();
        phone = data?['phone']?.toString() ?? data?['clientPhone']?.toString();
      }
    }

    final productDetails = <String, Map<String, dynamic>>{};
    final needsLookup = settings.showProductDescription ||
        settings.showProductNumberOnA4 ||
        settings.showExpiryDateOnA4 ||
        settings.showProductImageOnInvoice;

    if (needsLookup) {
      final products = invoice['products'] as List<dynamic>? ?? [];
      for (final item in products) {
        if (item is! Map) continue;
        final name = item['product']?.toString() ?? '';
        if (name.isEmpty || productDetails.containsKey(name)) continue;
        final query = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: name)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          productDetails[name] = query.docs.first.data();
        }
      }
    }

    return InvoicePrintContext(
      clientAddress: address,
      clientPhone: phone,
      productDetailsByName: productDetails,
    );
  }
}
