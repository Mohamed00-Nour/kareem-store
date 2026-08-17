import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/expense_local.dart';

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
    final Map<String, ExpenseLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = ExpenseLocal.fromFirestore(doc.id, doc.data());
    }
    await expensesBox.clear();
    await expensesBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastExpenseSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSync() async {
    final lastSyncStr = appMetaBox.get(HiveMetaKeys.lastExpenseSyncAt) as String?;
    if (lastSyncStr == null) {
      await fullSync();
      return;
    }
    final lastSync = DateTime.parse(lastSyncStr);
    final snap = await _fs
        .collection('expenses')
        .where('time', isGreaterThan: Timestamp.fromDate(lastSync))
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deleted'] == true) {
        await expensesBox.delete(doc.id);
      } else {
        await expensesBox.put(doc.id, ExpenseLocal.fromFirestore(doc.id, data));
      }
    }
    await appMetaBox.put(HiveMetaKeys.lastExpenseSyncAt, DateTime.now().toIso8601String());
  }
}
