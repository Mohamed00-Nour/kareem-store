class Product {
  String id;
  int randomNumber;
  String name;
  double sellingPrice1;
  double sellingPrice2;
  double sellingPrice3;
  double costPrice;
  int quantity;
  int alertAmount;
  String? image;

  Product({
    required this.id,
    required this.randomNumber,
    required this.name,
    required this.sellingPrice1,
    required this.sellingPrice2,
    required this.sellingPrice3,
    required this.costPrice,
    required this.quantity,
    required this.alertAmount,
    this.image,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'randomNumber': randomNumber,
      'name': name,
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'costPrice': costPrice,
      'quantity': quantity,
      'alertAmount': alertAmount,
      'image': image,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      randomNumber: map['randomNumber'],
      name: map['name'],
      sellingPrice1: map['sellingPrice1'],
      sellingPrice2: map['sellingPrice2'],
      sellingPrice3: map['sellingPrice3'],
      costPrice: map['costPrice'],
      quantity: map['quantity'],
      alertAmount: map['alertAmount'],
      image: map['image'],
    );
  }
}