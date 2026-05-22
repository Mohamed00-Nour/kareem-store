import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/Expenses.dart';

class ExpenseService {
  static final _db = FirebaseFirestore.instance;

  static const defaultCategories = [
    'مصاريف النقل',
    'مصاريف السائق',
    'مصاريف عامة',
  ];

  static CollectionReference<Map<String, dynamic>> get _expenses =>
      _db.collection('expenses');

  static CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('expense_categories');

  static Future<void> ensureDefaultCategories() async {
    final snap = await _categories.limit(1).get();
    if (snap.docs.isNotEmpty) return;
    final batch = _db.batch();
    for (final name in defaultCategories) {
      final ref = _categories.doc();
      batch.set(ref, {
        'name': name,
        'isDefault': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Stream<List<String>> categoriesStream() {
    return _categories.snapshots().map((snap) {
      final names = snap.docs
          .map((d) => d.data()['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      names.sort((a, b) => a.compareTo(b));
      return names;
    });
  }

  static Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final existing = await _categories.where('name', isEqualTo: trimmed).get();
    if (existing.docs.isNotEmpty) return;
    await _categories.add({
      'name': trimmed,
      'isDefault': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteCategory(String docId) async {
    await _categories.doc(docId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> categoriesDocsStream() {
    return _categories.snapshots();
  }

  static Stream<List<Expenses>> expensesStream() {
    return _expenses.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Expenses.fromMap(d.data(), id: d.id))
          .toList();
      list.sort((a, b) {
        final da = expenseDateFromData(a.toMap()) ?? DateTime(1970);
        final db = expenseDateFromData(b.toMap()) ?? DateTime(1970);
        return db.compareTo(da);
      });
      return list;
    });
  }

  static Future<void> saveExpense({
    String? id,
    required String category,
    required double amount,
    required DateTime date,
    String notes = '',
    Map<String, String> attributes = const {},
  }) async {
    final ref = id != null ? _expenses.doc(id) : _expenses.doc();
    final dateOnly = DateTime(date.year, date.month, date.day);
    await ref.set({
      'id': ref.id,
      'category': category.trim(),
      'name': category.trim(),
      'value': amount.toString(),
      'notes': notes.trim(),
      'attributes': attributes,
      'date': dateOnly.toIso8601String().split('T').first,
      'dateTimestamp': Timestamp.fromDate(dateOnly),
      'time': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await addCategory(category.trim());
  }

  static Future<void> deleteExpense(String id) async {
    await _expenses.doc(id).delete();
  }

  /// Parses expense date from Firestore document (supports legacy records).
  static DateTime? expenseDateFromData(Map<String, dynamic> data) {
    final ts = data['dateTimestamp'];
    if (ts is Timestamp) return ts.toDate();

    final time = data['time'];
    if (time is Timestamp) return time.toDate();

    final date = data['date'];
    if (date is Timestamp) return date.toDate();
    if (date is String && date.isNotEmpty) {
      final part = date.split(' ').first;
      return DateTime.tryParse(part);
    }
    return null;
  }

  static double expenseAmountFromData(Map<String, dynamic> data) {
    final v = data['value'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0.0;
  }

  static bool isExpenseInRange(
    Map<String, dynamic> data,
    DateTime start,
    DateTime end,
  ) {
    final d = expenseDateFromData(data);
    if (d == null) return true;
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Client-side filter: category, period, and text search.
  static List<Expenses> filterExpenses(
    List<Expenses> source, {
    String? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    String searchQuery = '',
  }) {
    var list = source;

    if (category != null && category.isNotEmpty) {
      list = list.where((e) => e.category == category).toList();
    }

    if (periodStart != null || periodEnd != null) {
      final start = periodStart != null
          ? DateTime(periodStart.year, periodStart.month, periodStart.day)
          : DateTime(1970);
      final end = periodEnd != null
          ? DateTime(
              periodEnd.year,
              periodEnd.month,
              periodEnd.day,
              23,
              59,
              59,
              999,
            )
          : DateTime(2100, 12, 31, 23, 59, 59, 999);
      list = list.where((e) {
        final d = expenseDateFromData(e.toMap());
        if (d == null) return periodStart == null;
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();
    }

    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        if (e.category.toLowerCase().contains(q)) return true;
        if (e.notes.toLowerCase().contains(q)) return true;
        if (e.date.toLowerCase().contains(q)) return true;
        if (e.amount.toString().contains(q)) return true;
        if (e.value.contains(q)) return true;
        for (final entry in e.attributes.entries) {
          if (entry.key.toLowerCase().contains(q) ||
              entry.value.toLowerCase().contains(q)) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    return list;
  }

  static double sumExpensesDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    DateTime? start,
    DateTime? end,
  }) {
    var total = 0.0;
    for (final doc in docs) {
      final data = doc.data();
      if (start != null && end != null && !isExpenseInRange(data, start, end)) {
        continue;
      }
      total += expenseAmountFromData(data);
    }
    return total;
  }
}
