// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'box_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BoxLocalAdapter extends TypeAdapter<BoxLocal> {
  @override
  final int typeId = 7;

  @override
  BoxLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BoxLocal(
      id: fields[0]?.toString() ?? '',
      value: (fields[1] as num?)?.toDouble() ?? 0.0,
      updatedAt: fields[2] is DateTime ? fields[2] as DateTime : DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, BoxLocal obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
