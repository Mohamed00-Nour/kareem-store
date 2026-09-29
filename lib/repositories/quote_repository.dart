import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/quote_local.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/firestore_sync_checkpoint.dart';
import '../sync/local_operation_journal.dart';

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

  Future<void> mergeCloud(String id, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'price_quotes/' + id;
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (appMetaBox.containsKey('executedQuote:' + id)) return;
        if (data == null || data['_deleted'] == true || data['deleted'] == true)
          await deleteLocal(id);
        else
          await upsertLocal(id, data);
        if (data != null) await CloudSnapshotGuard.record(path, data);
      });
  Future<void> fullSync() async {
    final snap = await _fs.collection('price_quotes').get();
    FirestoreReadDiagnostics.queryResult(
      'price_quotes (full)',
      snap.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snap.metadata.isFromCache,
    );
    for (final doc in snap.docs) await mergeCloud(doc.id, doc.data());
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt', 'createdAt'],
    );
    await appMetaBox.put(
        HiveMetaKeys.lastQuoteSyncAt, checkpoint.toIso8601String());
  }

  Future<void> deltaSync() async {
    final raw = appMetaBox.get(HiveMetaKeys.lastQuoteSyncAt)?.toString();
    final cursor = DateTime.tryParse(raw ?? '');
    if (cursor == null) {
      await fullSync();
      return;
    }
    final snap = await _fs
        .collection('price_quotes')
        .where('updatedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cursor))
        .get();
    FirestoreReadDiagnostics.queryResult(
      'price_quotes where updatedAt >= cursor',
      snap.docs.length,
      trigger: 'quote delta',
      fromCache: snap.metadata.isFromCache,
    );
    for (final doc in snap.docs) await mergeCloud(doc.id, doc.data());
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt'],
      floor: cursor,
    );
    await appMetaBox.put(
        HiveMetaKeys.lastQuoteSyncAt, checkpoint.toIso8601String());
  }
}
