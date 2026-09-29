import 'package:cloud_firestore/cloud_firestore.dart';

import '../local_db/hive_init.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/local_operation_journal.dart';

class SupplierVoucherRepository {
  static String _key(String id) => 'supplierVoucher:$id';

  static List<Map<String, dynamic>> getAll() => appMetaBox.keys
      .where((key) => key.toString().startsWith('supplierVoucher:'))
      .map((key) => Map<String, dynamic>.from(appMetaBox.get(key) as Map))
      .toList();

  static Map<String, dynamic>? findByNumber(int number, String direction) {
    for (final voucher in getAll()) {
      final raw = voucher['voucherNumber'];
      final voucherNumber =
          raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (voucherNumber == number && voucher['direction'] == direction) {
        return voucher;
      }
    }
    return null;
  }

  static Future<void> mergeCloud(String id, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'supplier_vouchers/$id';
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (data == null || data['_deleted'] == true) {
          await appMetaBox.delete(_key(id));
        } else {
          final local = Map<String, dynamic>.from(data);
          for (final field in ['date', 'timestamp']) {
            if (local[field] is Timestamp) {
              local[field] = (local[field] as Timestamp).toDate();
            }
          }
          local['id'] = id;
          await appMetaBox.put(_key(id), local);
          await CloudSnapshotGuard.record(path, data);
        }
      });

  static Future<void> fullSync() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('supplier_vouchers').get();
    FirestoreReadDiagnostics.queryResult(
      'supplier_vouchers (full)',
      snapshot.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snapshot.metadata.isFromCache,
    );
    for (final doc in snapshot.docs) {
      await mergeCloud(doc.id, doc.data());
    }
  }
}
