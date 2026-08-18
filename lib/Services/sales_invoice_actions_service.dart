import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../local_db/hive_init.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';

/// Delete / lookup sales invoices in [invoices] and client subcollections.
class SalesInvoiceActionsService {
  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      findClientSubInvoice({
    required String clientId,
    required String rootInvoiceId,
  }) async {
    final byField = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .where('invoiceId', isEqualTo: rootInvoiceId)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first;

    final all = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .get();
    for (final doc in all.docs) {
      if (doc.data()['invoiceId']?.toString() == rootInvoiceId) {
        return doc;
      }
    }
    return null;
  }

  /// Root invoice id (prefers [invoiceId] over embedded [id]).
  static String rootInvoiceIdFrom(Map<String, dynamic> invoice) {
    final fromField = invoice['invoiceId']?.toString().trim() ?? '';
    if (fromField.isNotEmpty) return fromField;
    return invoice['id']?.toString().trim() ?? '';
  }

  /// Loads the authoritative root invoice for edit mode.
  static Future<Map<String, dynamic>> buildEditPayload(
    Map<String, dynamic> invoice, {
    String? clientSubDocId,
  }) async {
    final collection = InvoiceSpecialService.sourceCollection(invoice);
    final rootId = rootInvoiceIdFrom(invoice);

    var payload = Map<String, dynamic>.from(invoice);
    payload['_sourceCollection'] = collection;
    if (clientSubDocId != null && clientSubDocId.isNotEmpty) {
      payload['_clientSubDocId'] = clientSubDocId;
    }
    if (rootId.isEmpty) return payload;

    final rootSnap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(rootId)
        .get();
    if (rootSnap.exists) {
      payload = {
        ...rootSnap.data()!,
        'id': rootId,
        '_sourceCollection': collection,
        if (clientSubDocId != null && clientSubDocId.isNotEmpty)
          '_clientSubDocId': clientSubDocId,
      };
    } else {
      payload['id'] = rootId;
      payload['_sourceCollection'] = collection;
    }
    return payload;
  }

  /// Deletes root invoice, matching client copy, restores stock, updates balance in Hive first.

  static Future<void> deleteSalesInvoice({
    required Map<String, dynamic> invoice,
    required String rootInvoiceId,
  }) async {
    final clientName = invoice['clientName']?.toString() ?? '';
    String clientId = invoice['clientId']?.toString() ?? '';
    if (clientId.isEmpty && clientName.isNotEmpty) {
      final localClient = ClientRepository.instance.findByName(clientName);
      clientId = localClient?.id ?? clientName;
    }

    final products = List<Map<String, dynamic>>.from(
      (invoice['products'] as List?) ?? [],
    );

    // 1. Delete invoice from local Hive cache
    await InvoiceRepository.instance.deleteSaleLocal(rootInvoiceId);

    // 2. Restore products stock in Hive
    for (final product in products) {
      final name = product['product']?.toString() ?? '';
      if (name.isEmpty) continue;
      final amount = invoiceNum(product['amount']);
      if (amount <= 0) continue;

      final localProd = ProductRepository.instance.findByName(name);
      if (localProd != null) {
        localProd.quantity += amount;
        await productsBox.put(localProd.id, localProd);
      }
    }

    // 3. Update client balance in Hive
    if (clientId.isNotEmpty) {
      final totalSum = invoiceNum(invoice['totalSum']);
      final paidAmount = invoiceNum(invoice['paidAmount']);
      final unpaid = totalSum - paidAmount;
      final localClient = ClientRepository.instance.getById(clientId) ?? ClientRepository.instance.findByName(clientName);
      if (localClient != null) {
        final newBal = localClient.balance - unpaid;
        await ClientRepository.instance.updateLocalBalance(localClient.id, newBal);
      }
      await BalanceHistoryRepository.instance.deleteForParent('client', clientId);
    }

    // 4. Enqueue background deletion to Firebase
    await SyncQueueManager.instance.enqueue(
      operationType: 'deleteInvoice',
      payload: {
        'clientId': clientId,
        'invoiceId': rootInvoiceId,
      },
    );

    // Trigger sync in background
    ConnectivityService.instance.forceSync();
  }
}

