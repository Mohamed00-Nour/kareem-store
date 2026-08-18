class Product {
  String id;
  int randomNumber;
  String name;
  String? description;
  double sellingPrice1;
  double sellingPrice2;
  double sellingPrice3;
  double costPrice;
  double quantity;
  int alertAmount;
  bool retail;
  String? image;

  Product({
    required this.id,
    required this.randomNumber,
    required this.name,
    this.description,
    required this.sellingPrice1,
    required this.sellingPrice2,
    required this.sellingPrice3,
    required this.costPrice,
    required this.quantity,
    required this.alertAmount,
    this.retail = false,
    this.image,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'randomNumber': randomNumber,
      'name': name,
      'description': description,
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'costPrice': costPrice,
      'quantity': quantity,
      'alertAmount': alertAmount,
      'retail': retail,
      'image': image,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      randomNumber: (map['randomNumber'] ?? 0).toInt(),
      name: map['name'] ?? '',
      description: map['description'],
      sellingPrice1: (map['sellingPrice1'] ?? 0.0).toDouble(),
      sellingPrice2: (map['sellingPrice2'] ?? 0.0).toDouble(),
      sellingPrice3: (map['sellingPrice3'] ?? 0.0).toDouble(),
      costPrice: (map['costPrice'] ?? 0.0).toDouble(),
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      alertAmount: (map['alertAmount'] ?? 0).toInt(),
      retail: map['retail'] == true,
      image: map['image'],
    );
  }
}
