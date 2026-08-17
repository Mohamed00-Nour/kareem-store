import 'package:hive/hive.dart';

part 'box_local.g.dart';

@HiveType(typeId: 7)
class BoxLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  double value;

  @HiveField(2)
  DateTime updatedAt;

  BoxLocal({
    required this.id,
    this.value = 0.0,
    required this.updatedAt,
  });

  factory BoxLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    return BoxLocal(
      id: docId,
      value: (data['value'] as num?)?.toDouble() ?? 0.0,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'value': value,
    };
  }
}
