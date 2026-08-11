import 'package:hive/hive.dart';

part 'sync_queue_item.g.dart';

/// All supported operation types in the sync queue.
enum SyncOperationType {
  createInvoice,
  editInvoice,
  deleteInvoice,
  createReturn,
  deleteReturn,
  adjustClientBalance,
  adjustSupplierBalance,
  createProduct,
  editProduct,
  deleteProduct,
  createQuote,
}

@HiveType(typeId: 3)
class SyncQueueItem extends HiveObject {
  /// Unique ID for this sync operation (UUID).
  @HiveField(0)
  String operationId;

  /// String representation of [SyncOperationType].
  @HiveField(1)
  String operationType;

  /// JSON-encoded payload of the operation data.
  @HiveField(2)
  String payloadJson;

  /// When this operation was created locally (offline).
  @HiveField(3)
  DateTime createdAt;

  /// Number of times this item has failed to sync.
  @HiveField(4)
  int retryCount;

  /// Human-readable status: 'pending', 'syncing', 'failed', 'synced'.
  @HiveField(5)
  String status;

  /// Error message from the last failed sync attempt, if any.
  @HiveField(6)
  String? lastError;

  SyncQueueItem({
    required this.operationId,
    required this.operationType,
    required this.payloadJson,
    required this.createdAt,
    this.retryCount = 0,
    this.status = 'pending',
    this.lastError,
  });
}
