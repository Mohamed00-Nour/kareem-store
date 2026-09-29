import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/customer_balance_store.dart';
import 'package:kareem_store/Services/customer_local_views.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/product_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/sync/local_operation_journal.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hive_startup_test_');
    await initHive(directory: directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('full startup reopens existing customer, metadata, and upload queue',
      () async {
    await clientsBox.put(
        'customer',
        ClientLocal(
            id: 'customer',
            name: 'Fixture',
            balance: 42,
            updatedAt: DateTime(2026, 1, 1)));
    await appMetaBox.put(CustomerBalanceStore.baseKey('customer'), 42.0);
    await syncQueueBox.put(
        'pending-upload',
        SyncQueueItem(
            operationId: 'pending-upload',
            operationType: 'createInvoice',
            payloadJson: '{}',
            createdAt: DateTime(2026, 1, 1),
            status: 'syncing'));
    await Hive.close();

    await initHive(directory: directory.path);
    await LocalOperationJournal.recover();
    await CustomerBalanceStore.preserveExistingBalances();
    await SyncQueueManager.instance.recoverInterruptedItems();

    expect(clientsBox.get('customer')!.balance, 42);
    expect(CustomerBalanceStore.balance('customer'), 42);
    expect(syncQueueBox.get('pending-upload')!.status, 'pending');
    expect(syncQueueBox.length, 1);
  });

  test('reopens a box that was already opened with the wrong generic type',
      () async {
    await productsBox.close();
    await Hive.openBox<dynamic>(HiveBoxNames.products);

    await initHive(directory: directory.path);

    expect(Hive.box<ProductLocal>(HiveBoxNames.products).isOpen, isTrue);
    expect(syncQueueBox.isOpen, isTrue);
  });

  test('large customer cache restores mirrors and list balances in one pass',
      () async {
    final clients = <dynamic, ClientLocal>{};
    final ledger = <String, dynamic>{};
    for (var index = 0; index < 300; index++) {
      final id = 'customer:$index';
      clients[id] = ClientLocal(
          id: id,
          name: 'Fixture $index',
          balance: 5,
          updatedAt: DateTime(2026, 1, 1));
      ledger[CustomerBalanceStore.baseKey(id)] = 5.0;
      ledger[CustomerBalanceStore.eventKey(id, 'event-$index')] = {
        'delta': 3.0
      };
    }
    await clientsBox.putAll(clients);
    await appMetaBox.putAll(ledger);
    await Hive.close();

    await initHive(directory: directory.path);
    await CustomerBalanceStore.preserveExistingBalances();

    final snapshot = CustomerLocalViews.snapshot();
    expect(snapshot.docs, hasLength(300));
    expect(snapshot.docs.every((doc) => doc['balance'] == 8.0), isTrue);
    expect(clientsBox.values.every((client) => client.balance == 8.0), isTrue);
    expect(CustomerBalanceStore.balance('customer:42'), 8.0);
  });
}
