import 'package:hive/hive.dart';

part 'department_local.g.dart';

@HiveType(typeId: 9)
class DepartmentLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime updatedAt;

  DepartmentLocal({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  factory DepartmentLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    return DepartmentLocal(
      id: docId,
      name: (data['name'] ?? data['departmentName'])?.toString() ?? '',
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}
