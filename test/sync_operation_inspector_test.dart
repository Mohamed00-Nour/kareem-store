import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/sync/financial_cloud_store.dart';
import 'package:kareem_store/sync/sync_operation_inspector.dart';

class _ReadOnlyCloud extends FinancialCloudStore {
  final Map<String, Map<String, dynamic>> documents;

  _ReadOnlyCloud(this.documents);

  @override
  Future<Map<String, dynamic>?> readDocument(String path) async =>
      documents[path];

  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
          String clientId) async =>
      const {};

  @override
  Future<Map<String, dynamic>> transaction(
          Future<Map<String, dynamic>> Function(FinancialTransaction tx)
              action) =>
      throw UnsupportedError('The inspector must remain read-only');
}

void main() {
  test('cloud inspector identifies receipt and operation-owned documents',
      () async {
    const operationId = 'operation-1';
    final item = SyncQueueItem(
      operationId: operationId,
      operationType: 'createInvoice',
      payloadJson: jsonEncode({
        'financialFormat': 2,
        'cloudWrites': [
          {'path': 'invoices/invoice-1', 'deleted': false},
          {'path': 'products/product-1', 'deleted': false},
        ],
      }),
      createdAt: DateTime(2026, 9, 28),
    );
    final cloud = _ReadOnlyCloud({
      'financial_operation_receipts/$operationId': {'operationId': operationId},
      'invoices/invoice-1': {'_operationId': operationId},
      'products/product-1': {'_operationId': 'newer-operation'},
    });

    final result = await SyncOperationInspector(store: cloud).inspect(item);

    expect(result.receiptExists, isTrue);
    expect(result.checks, hasLength(2));
    expect(result.checks.first.appliedBy(operationId), isTrue);
    expect(result.checks.last.appliedBy(operationId), isFalse);
  });

  test('Android backup cannot restore an old Hive synchronization queue', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
  });
}
