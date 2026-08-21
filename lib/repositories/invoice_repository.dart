import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/invoice_local.dart';

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
    await invoicesBox.put(id, InvoiceLocal.fromFirestore(id, data, defaultType: 'sale'));
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
    await returnInvoicesBox.put(id, InvoiceLocal.fromFirestore(id, data, defaultType: 'return'));
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

  List<InvoiceLocal> getBuyingBySupplier(String supplierId, {String? supplierName}) {
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
    await buyingInvoicesBox.put(id, InvoiceLocal.fromFirestore(id, data, defaultType: 'buying'));
  }

  Future<void> deleteBuyingLocal(String id) async {
    await buyingInvoicesBox.delete(id);
  }

  // ── Sync with Firestore ───────────────────────────────────────────────────

  Future<void> fullSyncSales() async {
    final snap = await _fs.collection('invoices').get();
    final Map<String, InvoiceLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = InvoiceLocal.fromFirestore(doc.id, doc.data(), defaultType: 'sale');
    }
    await invoicesBox.clear();
    await invoicesBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastInvoiceSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSyncSales() async {
    await fullSyncSales();
  }

  Future<void> fullSyncReturns() async {
    final snap = await _fs.collection('returnInvoices').get();
    final Map<String, InvoiceLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = InvoiceLocal.fromFirestore(doc.id, doc.data(), defaultType: 'return');
    }
    await returnInvoicesBox.clear();
    await returnInvoicesBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastReturnInvoiceSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSyncReturns() async {
    await fullSyncReturns();
  }

  Future<void> fullSyncBuying() async {
    final snap = await _fs.collection('buying invoices').get();
    final Map<String, InvoiceLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = InvoiceLocal.fromFirestore(doc.id, doc.data(), defaultType: 'buying');
    }
    await buyingInvoicesBox.clear();
    await buyingInvoicesBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastBuyingInvoiceSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSyncBuying() async {
    await fullSyncBuying();
  }
}
