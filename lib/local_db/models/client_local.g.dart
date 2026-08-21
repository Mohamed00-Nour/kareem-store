// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClientLocalAdapter extends TypeAdapter<ClientLocal> {
  @override
  final int typeId = 1;

  @override
  ClientLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ClientLocal(
      id: fields[0] as String,
      name: fields[1] as String,
      balance: fields[2] == null ? 0.0 : fields[2] as double,
      phone: fields[3] == null ? '' : fields[3] as String,
      address: fields[4] == null ? '' : fields[4] as String,
      updatedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ClientLocal obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.balance)
      ..writeByte(3)
      ..write(obj.phone)
      ..writeByte(4)
      ..write(obj.address)
      ..writeByte(5)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
