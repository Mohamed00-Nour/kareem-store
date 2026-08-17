import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/box_local.dart';

/// Repository for the main cash box (`box/mainBox`).
///
/// READ: Served immediately from Hive `boxCacheBox`.
/// WRITE: Updated in Hive, background-synced to Firestore.
/// SYNC: Fresh copy pulled from Firestore on startup/sync.
class BoxRepository {
  BoxRepository._();
  static final BoxRepository instance = BoxRepository._();

  static const String _mainBoxId = 'mainBox';
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  double getValue() {
    final doc = boxCacheBox.get(_mainBoxId);
    return doc?.value ?? 0.0;
  }

  Future<void> setValue(double newValue) async {
    final existing = boxCacheBox.get(_mainBoxId);
    if (existing != null) {
      existing.value = newValue;
      existing.updatedAt = DateTime.now();
      await existing.save();
    } else {
      await boxCacheBox.put(
        _mainBoxId,
        BoxLocal(id: _mainBoxId, value: newValue, updatedAt: DateTime.now()),
      );
    }
  }

  Future<void> increment(double amount) async {
    final current = getValue();
    await setValue(current + amount);
  }

  Future<void> decrement(double amount) async {
    final current = getValue();
    await setValue(current - amount);
  }

  Future<void> fullSync() async {
    try {
      final doc = await _fs.collection('box').doc(_mainBoxId).get();
      if (doc.exists && doc.data() != null) {
        await boxCacheBox.put(
          _mainBoxId,
          BoxLocal.fromFirestore(_mainBoxId, doc.data()!),
        );
      }
    } catch (_) {}
  }
}
