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
      id: fields[0] as String,
      parentId: fields[1] == null ? '' : fields[1] as String,
      parentType: fields[2] == null ? '' : fields[2] as String,
      enteredBalance: fields[3] == null ? 0.0 : fields[3] as double,
      balanceBefore: fields[4] == null ? 0.0 : fields[4] as double,
      type: fields[5] == null ? '' : fields[5] as String,
      invoiceId: fields[6] == null ? '' : fields[6] as String,
      invoiceNumber: fields[7] == null ? '' : fields[7] as String,
      timestamp: fields[8] as DateTime,
      direction: fields[9] == null ? '' : fields[9] as String,
      notes: fields[10] == null ? '' : fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, BalanceHistoryLocal obj) {
    writer
      ..writeByte(11)
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
      ..write(obj.direction)
      ..writeByte(10)
      ..write(obj.notes);
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
