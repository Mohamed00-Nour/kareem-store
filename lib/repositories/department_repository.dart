import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/department_local.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/firestore_sync_checkpoint.dart';

/// Repository for Departments.
///
/// READ: Served immediately from Hive `departmentsBox`.
/// WRITE: Saved to Hive, background-synced to Firestore.
/// SYNC: Syncs from Firestore.
class DepartmentRepository {
  DepartmentRepository._();
  static final DepartmentRepository instance = DepartmentRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  List<DepartmentLocal> getAll() {
    final list = departmentsBox.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  DepartmentLocal? getById(String id) => departmentsBox.get(id);

  Future<void> upsertLocal(String id, Map<String, dynamic> data) async {
    await departmentsBox.put(id, DepartmentLocal.fromFirestore(id, data));
  }

  Future<void> deleteLocal(String id) async {
    await departmentsBox.delete(id);
  }

  Future<void> fullSync() async {
    final snap = await _fs.collection('departments').get();
    FirestoreReadDiagnostics.queryResult(
      'departments (full)',
      snap.docs.length,
      trigger: 'compatibility bootstrap',
      fromCache: snap.metadata.isFromCache,
    );
    final Map<String, DepartmentLocal> map = {};
    for (final doc in snap.docs) {
      if (doc.data()['_deleted'] != true) {
        map[doc.id] = DepartmentLocal.fromFirestore(doc.id, doc.data());
      }
    }
    await departmentsBox.clear();
    await departmentsBox.putAll(map);
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt'],
    );
    await appMetaBox.put(
        HiveMetaKeys.lastDepartmentSyncAt, checkpoint.toIso8601String());
  }

  Future<void> deltaSync() async {
    final raw = appMetaBox.get(HiveMetaKeys.lastDepartmentSyncAt)?.toString();
    final cursor = DateTime.tryParse(raw ?? '');
    if (cursor == null) {
      await fullSync();
      return;
    }
    final snap = await _fs
        .collection('departments')
        .where('updatedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cursor))
        .get();
    FirestoreReadDiagnostics.queryResult(
      'departments where updatedAt >= cursor',
      snap.docs.length,
      trigger: 'department delta',
      fromCache: snap.metadata.isFromCache,
    );
    for (final doc in snap.docs) {
      if (doc.data()['_deleted'] == true) {
        await deleteLocal(doc.id);
      } else {
        await upsertLocal(doc.id, doc.data());
      }
    }
    final checkpoint = FirestoreSyncCheckpoint.newest(
      snap.docs.map((doc) => doc.data()),
      const ['updatedAt'],
      floor: cursor,
    );
    await appMetaBox.put(
        HiveMetaKeys.lastDepartmentSyncAt, checkpoint.toIso8601String());
  }
}
