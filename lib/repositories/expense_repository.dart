import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/expense_local.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/firestore_sync_checkpoint.dart';

/// Repository for Expenses and Expense Categories.
///
/// READ: Served immediately from Hive `expensesBox`.
/// WRITE: Saved to Hive, background-synced to Firestore.
/// SYNC: Delta / full sync from Firestore.
class ExpenseRepository {
  ExpenseRepository._();
  static final ExpenseRepository instance = ExpenseRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  List<ExpenseLocal> getAll() {
    final list = expensesBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  ExpenseLocal? getById(String id) => expensesBox.get(id);

  Future<void> upsertLocal(String id, Map<String, dynamic> data) async {
    await expensesBox.put(id, ExpenseLocal.fromFirestore(id, data));
  }

  Future<void> deleteLocal(String id) async {
    await expensesBox.delete(id);
  }

  List<String> getCategories() {
    final cats = expensesBox.values
        .map((e) => e.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    cats.sort();
    return cats;
  }

  Future<void> fullSync() async {
    final snap = await _fs.collection('expenses').get();
    FirestoreReadDiagnostics.queryResult(
      'expenses (full)',
      snap.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snap.metadata.isFromCache,
    );
    final Map<String, ExpenseLocal> map = {};
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deleted'] != true) {
        map[doc.id] = ExpenseLocal.fromFirestore(doc.id, data);
      }
    }
    await expensesBox.clear();
    await expensesBox.putAll(map);
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['time', 'updatedAt'],
    );
    await appMetaBox.put(
        HiveMetaKeys.lastExpenseSyncAt, checkpoint.toIso8601String());
  }

  Future<void> deltaSync() async {
    final lastSyncStr =
        appMetaBox.get(HiveMetaKeys.lastExpenseSyncAt) as String?;
    if (lastSyncStr == null) {
      await fullSync();
      return;
    }
    final lastSync = DateTime.parse(lastSyncStr);
    final snap = await _fs
        .collection('expenses')
        .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(lastSync))
        .get();
    FirestoreReadDiagnostics.queryResult(
      'expenses where time >= cursor',
      snap.docs.length,
      trigger: 'expense delta',
      fromCache: snap.metadata.isFromCache,
    );

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deleted'] == true) {
        await expensesBox.delete(doc.id);
      } else {
        await expensesBox.put(doc.id, ExpenseLocal.fromFirestore(doc.id, data));
      }
    }
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['time'],
      floor: lastSync,
    );
    await appMetaBox.put(
        HiveMetaKeys.lastExpenseSyncAt, checkpoint.toIso8601String());
  }
}
