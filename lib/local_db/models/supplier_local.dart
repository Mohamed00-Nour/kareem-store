import 'package:hive/hive.dart';

part 'supplier_local.g.dart';

@HiveType(typeId: 2)
class SupplierLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double balance;

  @HiveField(3)
  String phone;

  @HiveField(4)
  String address;

  @HiveField(5)
  DateTime updatedAt;

  SupplierLocal({
    required this.id,
    required this.name,
    this.balance = 0.0,
    this.phone = '',
    this.address = '',
    required this.updatedAt,
  });

  factory SupplierLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    return SupplierLocal(
      id: docId,
      name: data['name']?.toString() ?? '',
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      phone: data['phone']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      updatedAt: DateTime.now(),
    );
  }
}
