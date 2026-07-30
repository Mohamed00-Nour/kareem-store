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
      updatedAt: DateTime.now(),
    );
  }
}
