import 'dart:async';

import 'sales_invoices_fetch_service.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/client_repository.dart';
import '../local_db/hive_init.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';

/// Mark / list sales and return invoices flagged as special (مميزة).
class InvoiceSpecialService {
  static const salesCollection = 'invoices';
  static const returnCollection = 'returnInvoices';

  static bool isSpecial(Map<String, dynamic> invoice) =>
      invoice['isSpecial'] == true;

  static String sourceCollection(Map<String, dynamic> invoice) {
    final stored = invoice['_sourceCollection']?.toString();
    if (stored == returnCollection || stored == salesCollection) {
      return stored!;
    }
    if (invoice['invoiceType']?.toString() == 'return') {
      return returnCollection;
    }
    return salesCollection;
  }

  static String typeLabel(Map<String, dynamic> invoice) =>
      sourceCollection(invoice) == returnCollection ? 'مرتجع' : 'مبيعات';

  static Future<void> setSpecial({
    required String collection,
    required String docId,
    required String? clientName,
    required bool special,
    String? clientId,
    Map<String, dynamic>? invoiceData,
    String? clientSubDocId,
  }) async {
    // 1. Commit to Hive first so the action works instantly and offline.
    if (collection == returnCollection) {
      final local = returnInvoicesBox.get(docId);
      if (local != null) {
        local.isSpecial = special;
        await returnInvoicesBox.put(docId, local);
      } else if (invoiceData != null) {
        final data = Map<String, dynamic>.from(invoiceData)
          ..['isSpecial'] = special;
        await InvoiceRepository.instance.upsertReturnLocal(docId, data);
      }
    } else {
      final local = invoicesBox.get(docId);
      if (local != null) {
        local.isSpecial = special;
        await invoicesBox.put(docId, local);
      } else if (invoiceData != null) {
        final data = Map<String, dynamic>.from(invoiceData)
          ..['isSpecial'] = special;
        await InvoiceRepository.instance.upsertSaleLocal(docId, data);
      }
    }

    // 2. Persist the cloud change in the durable queue. ConnectivityService
    // drains it now when online, or automatically after connectivity returns.
    final client = clientName?.trim() ?? '';
    final localClient =
        client.isEmpty ? null : ClientRepository.instance.findByName(client);
    final resolvedClientId = clientId?.trim().isNotEmpty == true
        ? clientId!.trim()
        : (localClient?.id ?? client);
    await SyncQueueManager.instance.enqueue(
      operationType: 'updateInvoiceSpecial',
      payload: {
        'collection': collection,
        'invoiceId': docId,
        'clientId': resolvedClientId,
        'clientSubDocId': clientSubDocId?.trim() ?? '',
        'isSpecial': special,
      },
    );

    if (ConnectivityService.instance.isOnline) {
      unawaited(ConnectivityService.instance.forceSync());
    }
  }

  /// Synchronous Hive read used by live UI listeners.
  static List<Map<String, dynamic>> getSpecialInvoicesFromHive() {
    final results = <Map<String, dynamic>>[];
    final sales =
        InvoiceRepository.instance.getAllSales().where((i) => i.isSpecial);
    for (final inv in sales) {
      final map = inv.toMap();
      map['_sourceCollection'] = salesCollection;
      results.add(map);
    }
    final returns =
        InvoiceRepository.instance.getAllReturns().where((i) => i.isSpecial);
    for (final inv in returns) {
      final map = inv.toMap();
      map['_sourceCollection'] = returnCollection;
      results.add(map);
    }

    SalesInvoicesFetchService.sortNewestFirst(results);
    return results;
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialInvoices() async =>
      getSpecialInvoicesFromHive();
}
