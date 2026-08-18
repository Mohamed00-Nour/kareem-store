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
      id: fields[0]?.toString() ?? '',
      invoiceNumber: (fields[1] as num?)?.toInt() ?? 0,
      clientId: fields[2]?.toString() ?? '',
      clientName: fields[3]?.toString() ?? '',
      supplierId: fields[4]?.toString() ?? '',
      supplierName: fields[5]?.toString() ?? '',
      date: fields[6] is DateTime ? fields[6] as DateTime : DateTime.now(),
      totalSum: (fields[7] as num?)?.toDouble() ?? 0.0,
      paidAmount: (fields[8] as num?)?.toDouble() ?? 0.0,
      balance: (fields[9] as num?)?.toDouble() ?? 0.0,
      previousBalance: (fields[10] as num?)?.toDouble() ?? 0.0,
      profitMargin: (fields[11] as num?)?.toDouble() ?? 0.0,
      paymentMethod: fields[12]?.toString() ?? 'نقداً',
      notes: fields[13]?.toString() ?? '',
      invoiceDiscount: (fields[14] as num?)?.toDouble() ?? 0.0,
      invoiceType: fields[15]?.toString() ?? 'sale',
      isSpecial: fields[16] == true,
      productsJson: fields[17]?.toString() ?? '[]',
      updatedAt: fields[18] is DateTime ? fields[18] as DateTime : DateTime.now(),
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
