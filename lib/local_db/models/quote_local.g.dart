// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quote_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QuoteLocalAdapter extends TypeAdapter<QuoteLocal> {
  @override
  final int typeId = 6;

  @override
  QuoteLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuoteLocal(
      id: fields[0] as String,
      clientName: fields[1] as String,
      clientId: fields[2] as String,
      date: fields[3] as DateTime,
      totalSum: fields[4] as double,
      paidAmount: fields[5] as double,
      paymentMethod: fields[6] as String,
      notes: fields[7] as String,
      invoiceDiscount: fields[8] as double,
      discountIsPercent: fields[9] as bool,
      productsJson: fields[10] as String,
      createdAt: fields[11] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, QuoteLocal obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.clientName)
      ..writeByte(2)
      ..write(obj.clientId)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.totalSum)
      ..writeByte(5)
      ..write(obj.paidAmount)
      ..writeByte(6)
      ..write(obj.paymentMethod)
      ..writeByte(7)
      ..write(obj.notes)
      ..writeByte(8)
      ..write(obj.invoiceDiscount)
      ..writeByte(9)
      ..write(obj.discountIsPercent)
      ..writeByte(10)
      ..write(obj.productsJson)
      ..writeByte(11)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuoteLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
