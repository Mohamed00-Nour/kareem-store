// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InvoiceLocalAdapter extends TypeAdapter<InvoiceLocal> {
  @override
  final int typeId = 4;

  @override
  InvoiceLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InvoiceLocal(
      id: fields[0] as String,
      invoiceNumber: fields[1] as int,
      clientId: fields[2] as String,
      clientName: fields[3] as String,
      supplierId: fields[4] as String,
      supplierName: fields[5] as String,
      date: fields[6] as DateTime,
      totalSum: fields[7] as double,
      paidAmount: fields[8] as double,
      balance: fields[9] as double,
      previousBalance: fields[10] as double,
      profitMargin: fields[11] as double,
      paymentMethod: fields[12] as String,
      notes: fields[13] as String,
      invoiceDiscount: fields[14] as double,
      invoiceType: fields[15] as String,
      isSpecial: fields[16] as bool,
      productsJson: fields[17] as String,
      updatedAt: fields[18] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, InvoiceLocal obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.invoiceNumber)
      ..writeByte(2)
      ..write(obj.clientId)
      ..writeByte(3)
      ..write(obj.clientName)
      ..writeByte(4)
      ..write(obj.supplierId)
      ..writeByte(5)
      ..write(obj.supplierName)
      ..writeByte(6)
      ..write(obj.date)
      ..writeByte(7)
      ..write(obj.totalSum)
      ..writeByte(8)
      ..write(obj.paidAmount)
      ..writeByte(9)
      ..write(obj.balance)
      ..writeByte(10)
      ..write(obj.previousBalance)
      ..writeByte(11)
      ..write(obj.profitMargin)
      ..writeByte(12)
      ..write(obj.paymentMethod)
      ..writeByte(13)
      ..write(obj.notes)
      ..writeByte(14)
      ..write(obj.invoiceDiscount)
      ..writeByte(15)
      ..write(obj.invoiceType)
      ..writeByte(16)
      ..write(obj.isSpecial)
      ..writeByte(17)
      ..write(obj.productsJson)
      ..writeByte(18)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
