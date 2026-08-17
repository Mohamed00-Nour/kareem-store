import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/department_local.dart';

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
    final Map<String, DepartmentLocal> map = {};
    for (final doc in snap.docs) {
      map[doc.id] = DepartmentLocal.fromFirestore(doc.id, doc.data());
    }
    await departmentsBox.clear();
    await departmentsBox.putAll(map);
    await appMetaBox.put(HiveMetaKeys.lastDepartmentSyncAt, DateTime.now().toIso8601String());
  }

  Future<void> deltaSync() async {
    await fullSync();
  }
}
