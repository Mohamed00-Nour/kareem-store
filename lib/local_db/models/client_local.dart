import 'package:hive/hive.dart';

part 'client_local.g.dart';

@HiveType(typeId: 1)
class ClientLocal extends HiveObject {
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

  ClientLocal({
    required this.id,
    required this.name,
    this.balance = 0.0,
    this.phone = '',
    this.address = '',
    required this.updatedAt,
  });

  factory ClientLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    return ClientLocal(
      id: docId,
      name: data['name']?.toString() ?? '',
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      phone: data['phone']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      updatedAt: DateTime.now(),
    );
  }
}
