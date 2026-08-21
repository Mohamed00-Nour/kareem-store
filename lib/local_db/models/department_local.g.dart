// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'department_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DepartmentLocalAdapter extends TypeAdapter<DepartmentLocal> {
  @override
  final int typeId = 9;

  @override
  DepartmentLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DepartmentLocal(
      id: fields[0] as String,
      name: fields[1] as String,
      updatedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, DepartmentLocal obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DepartmentLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
