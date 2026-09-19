import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/invoice_local.dart';
import '../sync/sync_queue_manager.dart';

/// Repository for Invoices (Sales, Returns, and Buying).
///
/// READ: Served immediately from Hive boxes with zero network wait.
/// WRITE: Written to Hive first, enqueued for background sync to Firestore.
/// SYNC: Syncs from Firestore with delta queries where available.
class InvoiceRepository {
  InvoiceRepository._();
  static final InvoiceRepository instance = InvoiceRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Sales Invoices ────────────────────────────────────────────────────────

  List<InvoiceLocal> getAllSales() {
    final list = invoicesBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<InvoiceLocal> getSalesByClient(String clientId, {String? clientName}) {
    final cId = clientId.trim();
    final cName = (clientName ?? '').trim().toLowerCase();
    final list = invoicesBox.values.where((inv) {
      final invClientId = inv.clientId.trim();
      if (invClientId.isNotEmpty) {
        return cId.isNotEmpty && invClientId == cId;
      }
      if (cName.isNotEmpty && inv.clientName.trim().toLowerCase() == cName) {
        return true;
      }
      return false;
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  InvoiceLocal? getSaleById(String id) => invoicesBox.get(id);

  Future<void> upsertSaleLocal(String id, Map<String, dynamic> data) async {
    await invoicesBox.put(
        id, InvoiceLocal.fromFirestore(id, data, defaultType: 'sale'));
  }

  Future<void> deleteSaleLocal(String id) async {
    await invoicesBox.delete(id);
  }

  // ── Return Invoices ───────────────────────────────────────────────────────

  List<InvoiceLocal> getAllReturns() {
    final list = returnInvoicesBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<InvoiceLocal> getReturnsByClient(String clientId, {String? clientName}) {
    final cId = clientId.trim();
    final cName = (clientName ?? '').trim().toLowerCase();
    final list = returnInvoicesBox.values.where((inv) {
      final invClientId = inv.clientId.trim();
      if (invClientId.isNotEmpty) {
        return cId.isNotEmpty && invClientId == cId;
      }
      if (cName.isNotEmpty && inv.clientName.trim().toLowerCase() == cName) {
        return true;
      }
      return false;
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  InvoiceLocal? getReturnById(String id) => returnInvoicesBox.get(id);

  Future<void> upsertReturnLocal(String id, Map<String, dynamic> data) async {
    await returnInvoicesBox.put(
        id, InvoiceLocal.fromFirestore(id, data, defaultType: 'return'));
  }

  Future<void> deleteReturnLocal(String id) async {
    await returnInvoicesBox.delete(id);
  }

  // ── Buying Invoices ───────────────────────────────────────────────────────

  List<InvoiceLocal> getAllBuying() {
    final list = buyingInvoicesBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<InvoiceLocal> getBuyingBySupplier(String supplierId,
      {String? supplierName}) {
    final sId = supplierId.trim();
    final sName = (supplierName ?? '').trim().toLowerCase();
    final list = buyingInvoicesBox.values.where((inv) {
      final invSupplierId = inv.supplierId.trim();
      if (invSupplierId.isNotEmpty) {
        return sId.isNotEmpty && invSupplierId == sId;
      }
      if (sName.isNotEmpty && inv.supplierName.trim().toLowerCase() == sName) {
        return true;
      }
      return false;
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  InvoiceLocal? getBuyingById(String id) => buyingInvoicesBox.get(id);

  Future<void> upsertBuyingLocal(String id, Map<String, dynamic> data) async {
    await buyingInvoicesBox.put(
        id, InvoiceLocal.fromFirestore(id, data, defaultType: 'buying'));
  }

  Future<void> deleteBuyingLocal(String id) async {
    await buyingInvoicesBox.delete(id);
  }

  // ── Supplier Purchase Returns ───────────────────────────────────────

  List<InvoiceLocal> getBuyingReturnsBySupplier(
    String supplierId, {
    String? supplierName,
  }) {
    final sId = supplierId.trim();
    final sName = (supplierName ?? '').trim().toLowerCase();
    if (!Hive.isBoxOpen(HiveBoxNames.buyingReturnInvoices)) {
      return <InvoiceLocal>[];
    }
    final list = buyingReturnInvoicesBox.values.where((invoice) {
      if (invoice.supplierId.trim().isNotEmpty) {
        return invoice.supplierId.trim() == sId;
      }
      return sName.isNotEmpty &&
          invoice.supplierName.trim().toLowerCase() == sName;
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> upsertBuyingReturnLocal(
    String id,
    Map<String, dynamic> data,
  ) async {
    await buyingReturnInvoicesBox.put(
      id,
      InvoiceLocal.fromFirestore(id, data, defaultType: 'buying_return'),
    );
  }

  Future<void> deleteBuyingReturnLocal(String id) async {
    await buyingReturnInvoicesBox.delete(id);
  }

  // ── Sync with Firestore ───────────────────────────────────────────────────

  Future<void> fullSyncSales() async {
    final snap = await _fs.collection('invoices').get();
    final pendingSpecialIds = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'updateInvoiceSpecial',
      idKey: 'invoiceId',
    );
    final Map<String, InvoiceLocal> map = {};
    for (final doc in snap.docs) {
      final remote =
          InvoiceLocal.fromFirestore(doc.id, doc.data(), defaultType: 'sale');
      final local = invoicesBox.get(doc.id);
      if (pendingSpecialIds.contains(doc.id) && local != null) {
        remote.isSpecial = local.isSpecial;
      }
      map[doc.id] = remote;
    }
    await invoicesBox.putAll(map);
    await appMetaBox.put(
        HiveMetaKeys.lastInvoiceSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSyncSales() async {
    await fullSyncSales();
  }

  Future<void> fullSyncReturns() async {
    final snap = await _fs.collection('returnInvoices').get();
    final pendingSpecialIds = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'updateInvoiceSpecial',
      idKey: 'invoiceId',
    );
    final Map<String, InvoiceLocal> map = {};
    for (final doc in snap.docs) {
      final remote =
          InvoiceLocal.fromFirestore(doc.id, doc.data(), defaultType: 'return');
      final local = returnInvoicesBox.get(doc.id);
      if (pendingSpecialIds.contains(doc.id) && local != null) {
        remote.isSpecial = local.isSpecial;
      }
      map[doc.id] = remote;
    }
    await returnInvoicesBox.putAll(map);
    await appMetaBox.put(
        HiveMetaKeys.lastReturnInvoiceSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSyncReturns() async {
    await fullSyncReturns();
  }

  Future<void> fullSyncBuying() async {
    final results = await Future.wait([
      _fs.collection('buying invoices').get(),
      _fs.collectionGroup('buying invoices').get(),
    ]);

    final pendingCreates = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'createBuyingInvoice',
      idKey: 'invoiceId',
    );
    final pendingEdits = SyncQueueManager.instance.unfinishedEntityIds(
      operationType: 'editBuyingInvoice',
      idKey: 'invoiceId',
    );
    final pendingDeletes = <String>{
      ...SyncQueueManager.instance.unfinishedEntityIds(
        operationType: 'deleteBuyingInvoice',
        idKey: 'invoiceId',
      ),
      ...SyncQueueManager.instance.unfinishedEntityIds(
        operationType: 'deleteBuyingInvoice',
        idKey: 'supplierSubDocId',
      ),
    };
    final protectedIds = {...pendingCreates, ...pendingEdits};
    final protectedInvoiceNumbers = protectedIds
        .map((id) => buyingInvoicesBox.get(id)?.invoiceNumber ?? 0)
        .where((number) => number > 0)
        .toSet();

    final byIdentity = <String, InvoiceLocal>{};
    for (final doc in [...results[0].docs, ...results[1].docs]) {
      final data = Map<String, dynamic>.from(doc.data());
      final linkedId = data['invoiceId']?.toString().trim() ?? '';
      final storedId = data['id']?.toString().trim() ?? '';
      final canonicalId = linkedId.isNotEmpty
          ? linkedId
          : (storedId.isNotEmpty ? storedId : doc.id);
      if (pendingDeletes.contains(doc.id) ||
          pendingDeletes.contains(canonicalId) ||
          pendingDeletes.contains(storedId)) {
        continue;
      }

      final inferredSupplierId = doc.reference.parent.parent?.id.trim() ?? '';
      var supplierId = data['supplierId']?.toString().trim().isNotEmpty == true
          ? data['supplierId'].toString().trim()
          : inferredSupplierId;
      if (supplierId.isEmpty) {
        final supplierName =
            data['supplierName']?.toString().trim().toLowerCase() ?? '';
        if (supplierName.isNotEmpty) {
          for (final supplier in suppliersBox.values) {
            if (supplier.name.trim().toLowerCase() == supplierName) {
              supplierId = supplier.id;
              break;
            }
          }
        }
      }
      data['id'] = canonicalId;
      data['invoiceId'] = canonicalId;
      if (supplierId.isNotEmpty) data['supplierId'] = supplierId;

      final invoice = InvoiceLocal.fromFirestore(
        canonicalId,
        data,
        defaultType: 'buying',
      );
      final number = invoice.invoiceNumber;
      if (protectedIds.contains(doc.id) ||
          protectedIds.contains(canonicalId) ||
          protectedInvoiceNumbers.contains(number)) {
        continue;
      }
      final identity = number > 0
          ? '${invoice.supplierId}|number:$number'
          : '${invoice.supplierId}|id:$canonicalId';
      byIdentity.putIfAbsent(identity, () => invoice);
    }

    final cloudEntries = <String, InvoiceLocal>{
      for (final invoice in byIdentity.values) invoice.id: invoice,
    };
    for (final id in protectedIds) {
      final local = buyingInvoicesBox.get(id);
      if (local != null) cloudEntries[id] = local;
    }

    final retainedIds = cloudEntries.keys.toSet();
    final staleKeys = buyingInvoicesBox.keys.where((key) {
      final id = key.toString();
      return !retainedIds.contains(id) && !protectedIds.contains(id);
    }).toList(growable: false);
    await buyingInvoicesBox.deleteAll(staleKeys);
    await buyingInvoicesBox.putAll(cloudEntries);
    await appMetaBox.put(
      HiveMetaKeys.lastBuyingInvoiceSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> deltaSyncBuying() async {
    await fullSyncBuying();
  }

  Future<void> syncBuyingReturnsForSupplier(
    String supplierId, {
    String? supplierName,
  }) async {
    final snap = await _fs
        .collection('suppliers')
        .doc(supplierId)
        .collection('returnBuyingInvoices')
        .get();
    final entries = <String, InvoiceLocal>{};
    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      final canonicalId =
          data['invoiceId']?.toString().trim().isNotEmpty == true
              ? data['invoiceId'].toString().trim()
              : doc.id;
      data['supplierId'] = supplierId;
      if ((data['supplierName']?.toString().trim() ?? '').isEmpty &&
          supplierName != null) {
        data['supplierName'] = supplierName;
      }
      entries[canonicalId] = InvoiceLocal.fromFirestore(
        canonicalId,
        data,
        defaultType: 'buying_return',
      );
    }

    final staleKeys = buyingReturnInvoicesBox.values
        .where((invoice) => invoice.supplierId == supplierId)
        .where((invoice) => !entries.containsKey(invoice.id))
        .map((invoice) => invoice.key)
        .where((key) => key != null)
        .toList(growable: false);
    await buyingReturnInvoicesBox.deleteAll(staleKeys);
    await buyingReturnInvoicesBox.putAll(entries);
  }
}
