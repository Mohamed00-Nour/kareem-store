import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/local_operation_journal.dart';

class CustomerVoucherRepository {
  static Future<void> mergeCloud(String id, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'client_vouchers/' + id;
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (data == null || data['_deleted'] == true) {
          await appMetaBox.delete('customerVoucher:' + id);
        } else {
          await appMetaBox.put('customerVoucher:' + id, {
            ...data,
            'id': id,
            if (data['date'] is Timestamp)
              'date': (data['date'] as Timestamp).toDate()
          });
        }
        if (data != null) await CloudSnapshotGuard.record(path, data);
      });
  static Future<void> fullSync() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('client_vouchers').get();
    FirestoreReadDiagnostics.queryResult(
      'client_vouchers (full)',
      snapshot.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snapshot.metadata.isFromCache,
    );
    for (final doc in snapshot.docs) await mergeCloud(doc.id, doc.data());
  }
}
