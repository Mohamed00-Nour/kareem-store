// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'balance_history_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BalanceHistoryLocalAdapter extends TypeAdapter<BalanceHistoryLocal> {
  @override
  final int typeId = 8;

  @override
  BalanceHistoryLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BalanceHistoryLocal(
      id: fields[0]?.toString() ?? '',
      parentId: fields[1]?.toString() ?? '',
      parentType: fields[2]?.toString() ?? '',
      enteredBalance: (fields[3] as num?)?.toDouble() ?? 0.0,
      balanceBefore: (fields[4] as num?)?.toDouble() ?? 0.0,
      type: fields[5]?.toString() ?? '',
      invoiceId: fields[6]?.toString() ?? '',
      invoiceNumber: fields[7]?.toString() ?? '',
      timestamp: fields[8] is DateTime ? fields[8] as DateTime : DateTime.now(),
      direction: fields[9]?.toString() ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, BalanceHistoryLocal obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.parentId)
      ..writeByte(2)
      ..write(obj.parentType)
      ..writeByte(3)
      ..write(obj.enteredBalance)
      ..writeByte(4)
      ..write(obj.balanceBefore)
      ..writeByte(5)
      ..write(obj.type)
      ..writeByte(6)
      ..write(obj.invoiceId)
      ..writeByte(7)
      ..write(obj.invoiceNumber)
      ..writeByte(8)
      ..write(obj.timestamp)
      ..writeByte(9)
      ..write(obj.direction);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BalanceHistoryLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
