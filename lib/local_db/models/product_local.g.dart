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
      id: fields[0]?.toString() ?? '',
      name: fields[1]?.toString() ?? '',
      sellingPrice1: (fields[2] as num?)?.toDouble() ?? 0.0,
      sellingPrice2: (fields[3] as num?)?.toDouble() ?? 0.0,
      sellingPrice3: (fields[4] as num?)?.toDouble() ?? 0.0,
      quantity: (fields[5] as num?)?.toDouble() ?? 0.0,
      description: fields[6]?.toString() ?? '',
      costPrice: (fields[7] as num?)?.toDouble() ?? 0.0,
      barcode: fields[8]?.toString() ?? '',
      updatedAt: fields[9] is DateTime ? fields[9] as DateTime : DateTime.now(),
      alertAmount: (fields[10] as num?)?.toDouble() ?? 0.0,
      department: fields[11]?.toString() ?? '',
      randomNumber: (fields[12] as num?)?.toInt() ?? 0,
      onDemand: fields[13] == true,
      retail: fields[14] == true,
    );
  }

  @override
  void write(BinaryWriter writer, ProductLocal obj) {
    writer
      ..writeByte(15)
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
      ..write(obj.updatedAt)
      ..writeByte(10)
      ..write(obj.alertAmount)
      ..writeByte(11)
      ..write(obj.department)
      ..writeByte(12)
      ..write(obj.randomNumber)
      ..writeByte(13)
      ..write(obj.onDemand)
      ..writeByte(14)
      ..write(obj.retail);
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
