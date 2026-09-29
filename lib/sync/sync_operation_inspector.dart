import '../local_db/models/sync_queue_item.dart';
import 'financial_cloud_store.dart';
import 'sync_queue_manager.dart';

class SyncCloudCheck {
  final String path;
  final String action;
  final bool exists;
  final String? cloudOperationId;

  const SyncCloudCheck({
    required this.path,
    required this.action,
    required this.exists,
    this.cloudOperationId,
  });

  bool appliedBy(String operationId) => cloudOperationId == operationId;
}

class SyncOperationInspection {
  final bool receiptExists;
  final List<SyncCloudCheck> checks;

  const SyncOperationInspection({
    required this.receiptExists,
    required this.checks,
  });
}

/// Read-only cloud comparison for support and reconciliation. It never
/// changes Hive or Firebase and never treats a visual match as permission to
/// discard a financial operation. A receipt is the authoritative proof that
/// the operation committed.
class SyncOperationInspector {
  final FinancialCloudStore store;

  SyncOperationInspector({FinancialCloudStore? store})
      : store = store ?? FirestoreFinancialCloudStore();

  Future<SyncOperationInspection> inspect(SyncQueueItem item) async {
    final payload = SyncQueueManager.decodePayload(item);
    final receipt = await store
        .readDocument('financial_operation_receipts/${item.operationId}');
    final checks = <SyncCloudCheck>[];
    final writes = payload['cloudWrites'];
    if (writes is List) {
      for (final raw in writes) {
        if (raw is! Map) continue;
        final path = raw['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        final cloud = await store.readDocument(path);
        checks.add(SyncCloudCheck(
          path: path,
          action: raw['deleted'] == true ? 'delete' : 'write',
          exists: cloud != null && cloud['_deleted'] != true,
          cloudOperationId: cloud?['_operationId']?.toString(),
        ));
      }
    }
    return SyncOperationInspection(
      receiptExists: receipt != null,
      checks: checks,
    );
  }
}
