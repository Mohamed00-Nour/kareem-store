import 'package:hive/hive.dart';

part 'product_local.g.dart';

@HiveType(typeId: 0)
class ProductLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double sellingPrice1;

  @HiveField(3)
  double sellingPrice2;

  @HiveField(4)
  double sellingPrice3;

  @HiveField(5)
  double quantity;

  @HiveField(6)
  String description;

  @HiveField(7)
  double costPrice;

  @HiveField(8)
  String barcode;

  @HiveField(9)
  DateTime updatedAt;

  @HiveField(10)
  double alertAmount;

  @HiveField(11)
  String department;

  @HiveField(12)
  int randomNumber;

  @HiveField(13)
  bool onDemand;

  @HiveField(14)
  bool retail;

  ProductLocal({
    required this.id,
    required this.name,
    this.sellingPrice1 = 0.0,
    this.sellingPrice2 = 0.0,
    this.sellingPrice3 = 0.0,
    this.quantity = 0.0,
    this.description = '',
    this.costPrice = 0.0,
    this.barcode = '',
    this.alertAmount = 0.0,
    this.department = '',
    this.randomNumber = 0,
    this.onDemand = false,
    this.retail = false,
    required this.updatedAt,
  });

  factory ProductLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    return ProductLocal(
      id: docId,
      name: data['name']?.toString() ?? '',
      sellingPrice1: (data['sellingPrice1'] as num?)?.toDouble() ?? 0.0,
      sellingPrice2: (data['sellingPrice2'] as num?)?.toDouble() ?? 0.0,
      sellingPrice3: (data['sellingPrice3'] as num?)?.toDouble() ?? 0.0,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      description: data['description']?.toString() ?? '',
      costPrice: (data['costPrice'] as num?)?.toDouble() ?? 0.0,
      barcode: data['barcode']?.toString() ?? '',
      alertAmount: (data['alertAmount'] as num?)?.toDouble() ?? 0.0,
      department: data['department']?.toString() ?? '',
      randomNumber: (data['randomNumber'] as num?)?.toInt() ?? 0,
      onDemand: data['onDemand'] == true,
      retail: data['retail'] == true,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'quantity': quantity,
      'description': description,
      'costPrice': costPrice,
      'barcode': barcode,
      'alertAmount': alertAmount,
      'department': department,
      'randomNumber': randomNumber,
      'onDemand': onDemand,
      'retail': retail,
    };
  }
}
