import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/quote_local.dart';

/// Repository for Price Quotes.
///
/// READ: Served immediately from Hive `quotesBox`.
/// WRITE: Saved to Hive, background-synced to Firestore.
/// SYNC: Syncs from Firestore.
class QuoteRepository {
  QuoteRepository._();
  static final QuoteRepository instance = QuoteRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  List<QuoteLocal> getAll() {
    final list = quotesBox.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  QuoteLocal? getById(String id) => quotesBox.get(id);

  Future<void> upsertLocal(String id, Map<String, dynamic> data) async {
    await quotesBox.put(id, QuoteLocal.fromFirestore(id, data));
  }

  Future<void> deleteLocal(String id) async {
    await quotesBox.delete(id);
  }

  Future<void> fullSync() async {
    final snap = await _fs.collection('price_quotes').get();
    final Map<String, QuoteLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = QuoteLocal.fromFirestore(doc.id, doc.data());
    }
    await quotesBox.clear();
    await quotesBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastQuoteSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSync() async {
    final lastSyncStr = appMetaBox.get(HiveMetaKeys.lastQuoteSyncAt) as String?;
    if (lastSyncStr == null) {
      await fullSync();
      return;
    }
    final lastSync = DateTime.parse(lastSyncStr);
    final snap = await _fs
        .collection('price_quotes')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(lastSync))
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deleted'] == true) {
        await quotesBox.delete(doc.id);
      } else {
        await quotesBox.put(doc.id, QuoteLocal.fromFirestore(doc.id, data));
      }
    }
    await appMetaBox.put(HiveMetaKeys.lastQuoteSyncAt, DateTime.now().toIso8601String());
  }
}
