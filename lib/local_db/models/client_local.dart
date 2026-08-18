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
    final rawName = (data['clientName'] ?? data['name'])?.toString().trim() ?? '';
    final resolvedName = rawName.isNotEmpty ? rawName : docId;

    return ClientLocal(
      id: docId,
      name: resolvedName,
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      phone: (data['phone'] ?? data['clientPhone'])?.toString() ?? '',
      address: (data['address'] ?? data['clientAddress'])?.toString() ?? '',
      updatedAt: DateTime.now(),
    );
  }
}
