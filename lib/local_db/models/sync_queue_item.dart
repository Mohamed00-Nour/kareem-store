import 'package:hive/hive.dart';

part 'sync_queue_item.g.dart';

/// All supported operation types in the sync queue.
enum SyncOperationType {
  createInvoice,
  editInvoice,
  updateInvoiceSpecial,
  deleteInvoice,
  createReturn,
  deleteReturn,
  createBuyingInvoice,
  editBuyingInvoice,
  adjustClientBalance,
  adjustSupplierBalance,
  createProduct,
  editProduct,
  deleteProduct,
  createQuote,
  deleteQuote,
  saveExpense,
  deleteExpense,
  updateBox,
  createClient,
  createSupplier,
  updateStock,
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

  /// Stable, non-sensitive labels used by the sync dashboard. Keeping this
  /// snapshot with the operation means an invoice can still be identified
  /// after its local record is edited or deleted.
  @HiveField(7)
  String? diagnosticsJson;

  /// Append-only (and size-capped) history of upload attempts.
  @HiveField(8, defaultValue: '[]')
  String attemptHistoryJson;

  /// Machine-readable classification of [lastError].
  @HiveField(9)
  String? errorCategory;

  /// Firebase or local validation error code, when one is available.
  @HiveField(10)
  String? errorCode;

  /// Start time of the most recent upload attempt.
  @HiveField(11)
  DateTime? lastAttemptAt;

  /// Earliest time at which an automatic retry should run.
  @HiveField(12)
  DateTime? nextRetryAt;

  SyncQueueItem({
    required this.operationId,
    required this.operationType,
    required this.payloadJson,
    required this.createdAt,
    this.retryCount = 0,
    this.status = 'pending',
    this.lastError,
    this.diagnosticsJson,
    this.attemptHistoryJson = '[]',
    this.errorCategory,
    this.errorCode,
    this.lastAttemptAt,
    this.nextRetryAt,
  });
}
