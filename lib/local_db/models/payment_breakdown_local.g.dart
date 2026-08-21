// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_breakdown_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PaymentBreakdownLocalAdapter extends TypeAdapter<PaymentBreakdownLocal> {
  @override
  final int typeId = 10;

  @override
  PaymentBreakdownLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PaymentBreakdownLocal(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      wallet: fields[2] == null ? 0.0 : fields[2] as double,
      cash: fields[3] == null ? 0.0 : fields[3] as double,
      instapay: fields[4] == null ? 0.0 : fields[4] as double,
      bankTransfer: fields[5] == null ? 0.0 : fields[5] as double,
      notes: fields[6] == null ? '' : fields[6] as String,
      timestamp: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PaymentBreakdownLocal obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.wallet)
      ..writeByte(3)
      ..write(obj.cash)
      ..writeByte(4)
      ..write(obj.instapay)
      ..writeByte(5)
      ..write(obj.bankTransfer)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentBreakdownLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
