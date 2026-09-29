import 'package:cloud_firestore/cloud_firestore.dart';

/// Builds synchronization cursors only from timestamps that were actually
/// returned by Firestore.
///
/// Delta queries intentionally include the checkpoint timestamp again. This
/// small overlap makes equal server timestamps safe; merge/version guards make
/// replaying the boundary documents idempotent.
class FirestoreSyncCheckpoint {
  FirestoreSyncCheckpoint._();

  static final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime? dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime newest(
    Iterable<Map<String, dynamic>> documents,
    List<String> fields, {
    DateTime? floor,
  }) {
    var result = floor ?? epoch;
    for (final data in documents) {
      for (final field in fields) {
        final date = dateOf(data[field]);
        if (date != null && date.isAfter(result)) result = date;
      }
    }
    return result;
  }
}
