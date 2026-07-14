import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/printer_settings.dart';
import 'bluetooth_permission_service.dart';
import 'bluetooth_printer_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_print_formatter.dart';
import 'printer_settings_service.dart';

class InvoicePrintResult {
  final bool success;
  final String messageAr;

  const InvoicePrintResult({
    required this.success,
    this.messageAr = '',
  });
}

class InvoicePrintService {
  static Future<InvoicePrintResult> printSalesInvoice(
    Map<String, dynamic> invoice, {
    String? clientId,
  }) async {
    try {
      final settings = await PrinterSettingsService.load();
      if (settings.connectionType != PrinterConnectionType.bluetooth) {
        return const InvoicePrintResult(
          success: false,
          messageAr: 'نوع الاتصال ليس Bluetooth — راجع إعدادات الطابعة',
        );
      }
      if (settings.bluetoothMacAddress.trim().isEmpty) {
        return const InvoicePrintResult(
          success: false,
          messageAr: 'لم يتم حفظ عنوان MAC للطابعة',
        );
      }

      final prepared = await prepareForPrint(invoice, clientId: clientId);

      if ((prepared['products'] as List?)?.isEmpty ?? true) {
        return const InvoicePrintResult(
          success: false,
          messageAr: 'الفاتورة لا تحتوي على منتجات للطباعة',
        );
      }

      final hasPermission =
          await BluetoothPermissionService.hasPrinterBluetoothAccess();
      if (!hasPermission) {
        final granted =
            await BluetoothPermissionService.requestPrinterBluetoothAccess();
        if (!granted) {
          return const InvoicePrintResult(
            success: false,
            messageAr: 'يرجى السماح بالبلوتوث / الأجهزة القريبة',
          );
        }
      }

      if (!await BluetoothPrinterService.isBluetoothOn()) {
        return const InvoicePrintResult(
          success: false,
          messageAr: 'يرجى تشغيل البلوتوث على الهاتف',
        );
      }

      if (!await BluetoothPrinterService.isConnected()) {
        final connected = await BluetoothPrinterService.connect(
          settings.bluetoothMacAddress,
        );
        if (!connected) {
          return const InvoicePrintResult(
            success: false,
            messageAr:
                'تعذر الاتصال بالطابعة — تأكد أنها مشغّلة ومرتبطة بالهاتف',
          );
        }
      }

      final context = await _buildContext(prepared, settings);
      final ok = await BluetoothPrinterService.printSalesInvoice(
        invoice: prepared,
        settings: settings,
        context: context,
      );

      if (!ok) {
        return const InvoicePrintResult(
          success: false,
          messageAr: 'تعذر إرسال البيانات للطابعة — جرّب اختبار الطباعة من الإعدادات',
        );
      }

      return const InvoicePrintResult(success: true);
    } catch (e) {
      return InvoicePrintResult(
        success: false,
        messageAr: 'خطأ أثناء الطباعة: $e',
      );
    }
  }

  static Future<bool> tryAutoPrintAfterSave(
    Map<String, dynamic> invoice, {
    String? clientId,
  }) async {
    final settings = await PrinterSettingsService.load();
    if (!settings.printImmediatelyAfterSave) return false;
    final result = await printSalesInvoice(invoice, clientId: clientId);
    return result.success;
  }

  /// Normalizes invoice fields and merges main [invoices] doc when linked.
  static Future<Map<String, dynamic>> prepareForPrint(
    Map<String, dynamic> source, {
    String? clientId,
  }) async {
    var invoice = normalizeInvoice(source, clientName: clientId);

    final mainId =
        invoice['invoiceId']?.toString() ?? invoice['id']?.toString();
    if (mainId != null && mainId.isNotEmpty) {
      try {
        final mainDoc = await FirebaseFirestore.instance
            .collection('invoices')
            .doc(mainId)
            .get();
        final mainData = mainDoc.data();
        if (mainDoc.exists && mainData != null) {
          final main = Map<String, dynamic>.from(mainData);
          main['id'] = mainDoc.id;
          final subProducts = invoice['products'];
          invoice = normalizeInvoice(
            {...main, ...invoice},
            clientName: clientId ?? main['clientName']?.toString(),
          );
          if (subProducts is List && subProducts.isNotEmpty) {
            invoice['products'] = _normalizeProducts(subProducts);
          }
        }
      } catch (e) {
        // Ignored
      }
    }

    // Fetch and inject current balance of client or supplier
    final clientName = invoice['clientName']?.toString() ?? '';
    final supplierName = invoice['supplierName']?.toString() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;

    if (isSupplier) {
      final supplierId = invoice['supplierId']?.toString() ?? '';
      double? totalBalance;
      if (supplierId.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('suppliers')
              .doc(supplierId)
              .get();
          if (snap.exists) {
            totalBalance = (snap.data()?['totalBalance'] as num?)?.toDouble();
          }
        } catch (_) {}
      }
      if (totalBalance == null && supplierName.isNotEmpty) {
        try {
          final query = await FirebaseFirestore.instance
              .collection('suppliers')
              .where('name', isEqualTo: supplierName)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            totalBalance = (query.docs.first.data()['totalBalance'] as num?)?.toDouble();
          }
        } catch (_) {}
      }
      if (totalBalance != null) {
        invoice['currentSupplierBalance'] = totalBalance;
      }
    }

    return invoice;
  }

  static Map<String, dynamic> normalizeInvoice(
    Map<String, dynamic> raw, {
    String? clientName,
  }) {
    final invoice = Map<String, dynamic>.from(raw);

    if (clientName != null && clientName.trim().isNotEmpty) {
      invoice['clientName'] = clientName.trim();
    }
    invoice['clientName'] ??= '';

    invoice['products'] = _normalizeProducts(invoice['products']);

    for (final key in [
      'totalSum',
      'paidAmount',
      'balance',
      'previousBalance',
      'profitMargin',
      'invoiceDiscount',
    ]) {
      if (invoice.containsKey(key) && invoice[key] != null) {
        invoice[key] = _toDouble(invoice[key]);
      }
    }

    if (!invoice.containsKey('previousBalance') ||
        invoice['previousBalance'] == null) {
      invoice['previousBalance'] = 0.0;
    }

    return invoice;
  }

  static List<Map<String, dynamic>> _normalizeProducts(dynamic products) {
    if (products is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in products) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      map['product'] = map['product']?.toString() ?? '';
      map['amount'] = map['amount']?.toString() ?? '0';
      map['selectedPrice'] = _toDouble(map['selectedPrice']);
      map['total'] = _toDouble(map['total']);
      if (map['product'].toString().isEmpty) continue;
      out.add(map);
    }
    return out;
  }

  static Future<InvoicePrintContext> _buildContext(
    Map<String, dynamic> invoice,
    PrinterSettings settings,
  ) async {
    String? address;
    String? phone;
    final clientName = invoice['clientName']?.toString() ?? '';

    if (settings.showCustomerAddressAndPhone && clientName.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('clients')
          .where('clientName', isEqualTo: clientName)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        address = data['address']?.toString() ??
            data['clientAddress']?.toString();
        phone =
            data['phone']?.toString() ?? data['clientPhone']?.toString();
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

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
