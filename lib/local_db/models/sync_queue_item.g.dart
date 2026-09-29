// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_queue_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncQueueItemAdapter extends TypeAdapter<SyncQueueItem> {
  @override
  final int typeId = 3;

  @override
  SyncQueueItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncQueueItem(
      operationId: fields[0] as String,
      operationType: fields[1] as String,
      payloadJson: fields[2] as String,
      createdAt: fields[3] as DateTime,
      retryCount: fields[4] as int,
      status: fields[5] as String,
      lastError: fields[6] as String?,
      diagnosticsJson: fields[7] as String?,
      attemptHistoryJson: fields[8] as String? ?? '[]',
      errorCategory: fields[9] as String?,
      errorCode: fields[10] as String?,
      lastAttemptAt: fields[11] as DateTime?,
      nextRetryAt: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncQueueItem obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.operationId)
      ..writeByte(1)
      ..write(obj.operationType)
      ..writeByte(2)
      ..write(obj.payloadJson)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.retryCount)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.lastError)
      ..writeByte(7)
      ..write(obj.diagnosticsJson)
      ..writeByte(8)
      ..write(obj.attemptHistoryJson)
      ..writeByte(9)
      ..write(obj.errorCategory)
      ..writeByte(10)
      ..write(obj.errorCode)
      ..writeByte(11)
      ..write(obj.lastAttemptAt)
      ..writeByte(12)
      ..write(obj.nextRetryAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncQueueItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
