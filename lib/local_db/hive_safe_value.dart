import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts Firestore-only values into types Hive can persist without a
/// custom adapter. Financial event snapshots commonly contain [Timestamp].
dynamic hiveSafeValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is Map) {
    return <dynamic, dynamic>{
      for (final entry in value.entries) entry.key: hiveSafeValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(hiveSafeValue).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> hiveSafeMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(hiveSafeValue(value) as Map);
