// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductLocalAdapter extends TypeAdapter<ProductLocal> {
  @override
  final int typeId = 0;

  @override
  ProductLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProductLocal(
      id: fields[0] as String,
      name: fields[1] as String,
      sellingPrice1: fields[2] as double,
      sellingPrice2: fields[3] as double,
      sellingPrice3: fields[4] as double,
      quantity: fields[5] as double,
      description: fields[6] as String,
      costPrice: fields[7] as double,
      barcode: fields[8] as String,
      updatedAt: fields[9] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ProductLocal obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.sellingPrice1)
      ..writeByte(3)
      ..write(obj.sellingPrice2)
      ..writeByte(4)
      ..write(obj.sellingPrice3)
      ..writeByte(5)
      ..write(obj.quantity)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.costPrice)
      ..writeByte(8)
      ..write(obj.barcode)
      ..writeByte(9)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
