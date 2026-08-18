// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseLocalAdapter extends TypeAdapter<ExpenseLocal> {
  @override
  final int typeId = 5;

  @override
  ExpenseLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseLocal(
      id: fields[0]?.toString() ?? '',
      category: fields[1]?.toString() ?? '',
      amount: (fields[2] as num?)?.toDouble() ?? 0.0,
      date: fields[3] is DateTime ? fields[3] as DateTime : DateTime.now(),
      notes: fields[4]?.toString() ?? '',
      attributesJson: fields[5]?.toString() ?? '{}',
      updatedAt: fields[6] is DateTime ? fields[6] as DateTime : DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseLocal obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.attributesJson)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
