import 'dart:convert';
import '../local_db/hive_init.dart';

/// Guards are persisted separately from typed legacy Hive models.
class CloudSnapshotGuard {
  static String versionKey(String path) => 'cloudVersion:$path';
  static String operationKey(String path) => 'cloudOperation:$path';
  static bool pendingPath(String path) {
    for (final item in syncQueueBox.values) {
      try {
        final data = jsonDecode(item.payloadJson) as Map;
        if (data['financialFormat'] == 2) {
          if ((data['cloudWrites'] as List).any((w) => w['path'] == path) ||
              (data['customerDeltas'] as Map)
                  .keys
                  .any((id) => path == 'clients/$id') ||
              (data['supplierDeltas'] as Map? ?? const {})
                  .keys
                  .any((id) => path == 'suppliers/$id')) return true;
        } else {
          final id = data['invoiceId'];
          if (path == 'buying invoices/$id' &&
              [
                'createBuyingInvoice',
                'editBuyingInvoice',
                'deleteBuyingInvoice'
              ].contains(item.operationType)) return true;
          if (path == 'price_quotes/' + (data['quoteId']?.toString() ?? '') &&
              ['createQuote', 'editQuote', 'deleteQuote']
                  .contains(item.operationType)) return true;
          if (path.startsWith('products/') &&
              path.split('/').length == 2 &&
              [
                'createInvoice',
                'editInvoice',
                'deleteInvoice',
                'createReturn',
                'deleteReturn',
                'createBuyingInvoice',
                'editBuyingInvoice',
                'deleteBuyingInvoice'
              ].contains(item.operationType)) return true;
          if ((path == 'invoices/$id' || path == 'returnInvoices/$id') &&
              [
                'createInvoice',
                'editInvoice',
                'deleteInvoice',
                'createReturn',
                'deleteReturn',
                'deleteReturnInvoice',
                'updateInvoiceSpecial'
              ].contains(item.operationType)) return true;
          if (path == 'clients/${data['clientId']}' && data['clientId'] != null)
            return true;
          final supplierId = data['supplierId']?.toString() ?? '';
          if (supplierId.isNotEmpty &&
              (path == 'suppliers/$supplierId' ||
                  path.startsWith('suppliers/$supplierId/balanceHistory/')) &&
              [
                'createSupplier',
                'createBuyingInvoice',
                'editBuyingInvoice',
                'deleteBuyingInvoice',
                'adjustSupplierBalance'
              ].contains(item.operationType)) return true;
          if (path == 'products/${data['productId']}' &&
              data['productId'] != null) return true;
          if (path == 'box/mainBox' &&
              [
                'updateBox',
                'createInvoice',
                'editInvoice',
                'deleteInvoice',
                'createReturn',
                'deleteReturn',
                'deleteReturnInvoice',
                'adjustClientBalance',
                'createBuyingInvoice',
                'editBuyingInvoice',
                'deleteBuyingInvoice',
                'adjustSupplierBalance'
              ].contains(item.operationType)) return true;
        }
      } catch (_) {/* malformed operations remain visible in the queue */}
    }
    return false;
  }

  static bool accepts(String path, Map<String, dynamic>? data) {
    if (pendingPath(path)) return false;
    final localVersion =
        appMetaBox.get(versionKey(path), defaultValue: 0) as num;
    if (data == null)
      return localVersion == 0; // versioned deletions use tombstones
    final remoteVersion = (data['_version'] as num?) ?? 0;
    return remoteVersion >= localVersion;
  }

  static Future<void> record(String path, Map<String, dynamic> data) async {
    await appMetaBox.put(versionKey(path), (data['_version'] as num?) ?? 0);
    if (data['_operationId'] != null)
      await appMetaBox.put(operationKey(path), data['_operationId']);
  }

  static Future<void> acknowledge(Map<String, dynamic> receipt) async {
    for (final entry in (receipt['versions'] as Map).entries) {
      final key = versionKey(entry.key.toString());
      final previous = (appMetaBox.get(key, defaultValue: 0) as num).toInt();
      if ((entry.value as num).toInt() > previous)
        await appMetaBox.put(key, entry.value);
    }
    await appMetaBox.flush();
  }
}
