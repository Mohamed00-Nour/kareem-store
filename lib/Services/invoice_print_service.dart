import '../models/printer_settings.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import 'bluetooth_permission_service.dart';
import 'bluetooth_printer_service.dart';
import 'invoice_print_formatter.dart';
import 'printer_settings_service.dart';
import 'sales_invoice_actions_service.dart';

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
      final settings = PrinterSettingsService.current;
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
          messageAr:
              'تعذر إرسال البيانات للطابعة — جرّب اختبار الطباعة من الإعدادات',
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
    final settings = PrinterSettingsService.current;
    if (!settings.printImmediatelyAfterSave) return false;
    final result = await printSalesInvoice(invoice, clientId: clientId);
    return result.success;
  }

  /// Builds the printable invoice from the latest Hive record. The supplied
  /// map is only a fallback for unsaved previews or records absent from Hive.
  /// Printing never waits for an upload or a Firestore read.
  static Future<Map<String, dynamic>> prepareForPrint(
    Map<String, dynamic> source, {
    String? clientId,
  }) async {
    var invoice = normalizeInvoice(source);

    final mainId =
        invoice['invoiceId']?.toString() ?? invoice['id']?.toString();
    if (mainId != null && mainId.isNotEmpty) {
      // 1. Try local Hive first (primary DB — always has latest data)
      final localSale = InvoiceRepository.instance.getSaleById(mainId);
      final localReturn = localSale == null
          ? InvoiceRepository.instance.getReturnById(mainId)
          : null;
      final localBuying = (localSale == null && localReturn == null)
          ? InvoiceRepository.instance.getBuyingById(mainId)
          : null;

      final localInvoice = localSale ?? localReturn ?? localBuying;
      if (localInvoice != null) {
        final localMap = localInvoice.toMap();
        localMap['id'] = mainId;
        invoice = normalizeInvoice(
          {...invoice, ...localMap},
        );
      }
    }

    return _enrichFromHive(invoice, clientId: clientId);
  }

  static Map<String, dynamic> _enrichFromHive(
    Map<String, dynamic> invoice, {
    String? clientId,
  }) {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final supplierName = invoice['supplierName']?.toString().trim() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;

    if (isSupplier) {
      final supplierId = invoice['supplierId']?.toString().trim() ?? '';
      final supplier = (supplierId.isNotEmpty
              ? SupplierRepository.instance.getById(supplierId)
              : null) ??
          SupplierRepository.instance.findByName(supplierName);
      if (supplier != null) {
        invoice['supplierId'] = supplier.id;
        invoice['supplierName'] = supplier.name;
        invoice['currentSupplierBalance'] = supplier.balance;
      }
      return invoice;
    }

    final storedClientId = invoice['clientId']?.toString().trim() ?? '';
    final client = (storedClientId.isNotEmpty
            ? ClientRepository.instance.getById(storedClientId)
            : null) ??
        (clientId != null
            ? ClientRepository.instance.getById(clientId) ??
                ClientRepository.instance.findByName(clientId)
            : null) ??
        (clientName.isNotEmpty
            ? ClientRepository.instance.findByName(clientName)
            : null);
    if (client != null) {
      invoice['clientId'] = client.id;
      invoice['clientName'] = client.name;
    }
    return SalesInvoiceActionsService.buildClientPagePayload(invoice);
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
      // 1. Try local Hive first (instant, 0ms)
      final localClient = ClientRepository.instance.findByName(clientName);
      if (localClient != null) {
        phone = localClient.phone.isNotEmpty ? localClient.phone : null;
        address = localClient.address.isNotEmpty ? localClient.address : null;
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

        // 1. Try local Hive first
        final localProd = ProductRepository.instance.findByName(name);
        if (localProd != null) {
          productDetails[name] = {
            'name': localProd.name,
            'costPrice': localProd.costPrice,
            'quantity': localProd.quantity,
            'description': localProd.description,
          };
          continue;
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
