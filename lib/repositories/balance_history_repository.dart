import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';

/// Repository for Client & Supplier Balance History entries.
///
/// READ: Served immediately from Hive `balanceHistoryBox`.
/// WRITE: Stored locally, synced in background.
class BalanceHistoryRepository {
  BalanceHistoryRepository._();
  static final BalanceHistoryRepository instance = BalanceHistoryRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static String _boxKey(String parentType, String parentId, String docId) =>
      '${parentType}_${parentId}_$docId';

  List<BalanceHistoryLocal> getForClient(String clientId) {
    final cId = clientId.trim();
    final list = balanceHistoryBox.values
        .where((e) => e.parentType == 'client' && e.parentId == cId)
        .toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Deduplicate by entry ID or invoiceId + type
    final seenKeys = <String>{};
    final deduplicated = <BalanceHistoryLocal>[];
    for (final item in list) {
      final key = item.invoiceId.isNotEmpty
          ? '${item.invoiceId}_${item.type}'
          : item.id;
      if (seenKeys.add(key)) {
        deduplicated.add(item);
      }
    }
    return deduplicated;
  }

  List<BalanceHistoryLocal> getForSupplier(String supplierId) {
    final sId = supplierId.trim();
    final list = balanceHistoryBox.values
        .where((e) => e.parentType == 'supplier' && e.parentId == sId)
        .toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Deduplicate by entry ID or invoiceId + type
    final seenKeys = <String>{};
    final deduplicated = <BalanceHistoryLocal>[];
    for (final item in list) {
      final key = item.invoiceId.isNotEmpty
          ? '${item.invoiceId}_${item.type}'
          : item.id;
      if (seenKeys.add(key)) {
        deduplicated.add(item);
      }
    }
    return deduplicated;
  }

  Future<void> upsertLocal(BalanceHistoryLocal entry) async {
    final key = _boxKey(entry.parentType, entry.parentId, entry.id);
    await balanceHistoryBox.put(key, entry);
  }

  Future<void> deleteLocal(String parentType, String parentId, String docId) async {
    final key = _boxKey(parentType, parentId, docId);
    await balanceHistoryBox.delete(key);
  }

  Future<void> deleteByInvoiceId(String parentType, String parentId, String invoiceId) async {
    final keysToDelete = balanceHistoryBox.values
        .where((e) =>
            e.parentType == parentType &&
            e.parentId == parentId &&
            (e.id == invoiceId ||
             e.id == '${invoiceId}_sale' ||
             e.id == '${invoiceId}_pay' ||
             e.id == '${invoiceId}_return' ||
             e.id == '${invoiceId}_return_pay'))
        .map((e) => _boxKey(e.parentType, e.parentId, e.id))
        .toList();
    await balanceHistoryBox.deleteAll(keysToDelete);
  }

  Future<void> deleteForParent(String parentType, String parentId) async {
    final keysToDelete = balanceHistoryBox.values
        .where((e) => e.parentType == parentType && e.parentId == parentId)
        .map((e) => _boxKey(e.parentType, e.parentId, e.id))
        .toList();
    await balanceHistoryBox.deleteAll(keysToDelete);
  }

  Future<void> fullSyncForClient(String clientId) async {
    final snap = await _fs
        .collection('clients')
        .doc(clientId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs) {
      final entry = BalanceHistoryLocal.fromFirestore(
        doc.id,
        clientId,
        'client',
        doc.data(),
      );
      await upsertLocal(entry);
    }
  }

  Future<void> fullSyncForSupplier(String supplierId) async {
    final snap = await _fs
        .collection('suppliers')
        .doc(supplierId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs) {
      final entry = BalanceHistoryLocal.fromFirestore(
        doc.id,
        supplierId,
        'supplier',
        doc.data(),
      );
      await upsertLocal(entry);
    }
  }
}
