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
      id: fields[0]?.toString() ?? '',
      clientName: fields[1]?.toString() ?? '',
      clientId: fields[2]?.toString() ?? '',
      date: fields[3] is DateTime ? fields[3] as DateTime : DateTime.now(),
      totalSum: (fields[4] as num?)?.toDouble() ?? 0.0,
      paidAmount: (fields[5] as num?)?.toDouble() ?? 0.0,
      paymentMethod: fields[6]?.toString() ?? 'نقداً',
      notes: fields[7]?.toString() ?? '',
      invoiceDiscount: (fields[8] as num?)?.toDouble() ?? 0.0,
      discountIsPercent: fields[9] == true,
      productsJson: fields[10]?.toString() ?? '[]',
      createdAt: fields[11] is DateTime ? fields[11] as DateTime : DateTime.now(),
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
