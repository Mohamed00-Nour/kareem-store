import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/repositories/client_repository.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('customer_regression_');
    Hive.init(directory.path);
    Hive.registerAdapter(ClientLocalAdapter());
    Hive.registerAdapter(InvoiceLocalAdapter());
    Hive.registerAdapter(BalanceHistoryLocalAdapter());
    Hive.registerAdapter(SyncQueueItemAdapter());
    await Hive.openBox<ClientLocal>(HiveBoxNames.clients);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.invoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.returnInvoices);
    await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
    await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
    await Hive.openBox(HiveBoxNames.appMeta);
  });
  setUp(() async {
    await clientsBox.clear();
    await invoicesBox.clear();
    await returnInvoicesBox.clear();
    await balanceHistoryBox.clear();
    await syncQueueBox.clear();
    await appMetaBox.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test('reading history retains invoice entries when cache is incomplete',
      () async {
    await BalanceHistoryRepository.instance.upsertLocal(BalanceHistoryLocal(
      id: 'legacy-sale',
      parentId: 'c',
      parentType: 'client',
      type: 'sale',
      invoiceId: 'not-yet-cached',
      enteredBalance: 100,
      timestamp: DateTime(2026, 1, 1),
    ));
    expect(BalanceHistoryRepository.instance.getForClient('c'), hasLength(1));
    await balanceHistoryBox.flush();
    expect(balanceHistoryBox.length, 1);
  });
  test('two distinct invoice IDs with one display number both count', () async {
    for (final id in ['device-a', 'device-b']) {
      await invoicesBox.put(
          id,
          InvoiceLocal(
            id: id,
            clientId: 'c',
            invoiceNumber: 1,
            totalSum: 100,
            date: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ));
    }
    expect(BalanceHistoryRepository.instance.calculateClientBalance('c'), 200);
  });
  test(
      'uncached invoice with matching display number is not discarded as a duplicate',
      () async {
    await invoicesBox.put(
        'cached',
        InvoiceLocal(
            id: 'cached',
            clientId: 'c',
            invoiceNumber: 1,
            totalSum: 100,
            date: DateTime(2026),
            updatedAt: DateTime(2026)));
    await BalanceHistoryRepository.instance.upsertLocal(BalanceHistoryLocal(
        id: 'uncached-sale',
        parentId: 'c',
        parentType: 'client',
        type: 'sale',
        invoiceId: 'another-invoice',
        invoiceNumber: '1',
        enteredBalance: 50,
        timestamp: DateTime(2026)));
    expect(BalanceHistoryRepository.instance.getForClient('c'), hasLength(2));
    expect(balanceHistoryBox.length, 1);
  });
  test('cloud upsert cannot replace a locally pending customer balance',
      () async {
    await ClientRepository.instance
        .upsertLocal('c', {'clientName': 'Test', 'balance': 150.0});
    await appMetaBox.put('customerBalanceBase:c', 150.0);
    await syncQueueBox.put(
        'pending',
        SyncQueueItem(
          operationId: 'pending',
          operationType: 'adjustClientBalance',
          payloadJson: '{"clientId":"c","amount":50,"isAddition":true}',
          createdAt: DateTime(2026, 1, 1),
        ));
    // This is the exact repository method called by the old realtime listener.
    await ClientRepository.instance
        .upsertLocal('c', {'clientName': 'Test', 'balance': 100.0});
    expect(clientsBox.get('c')!.balance, 150);
  });

  test('timestamped customer tombstone hides profile but retains ledger',
      () async {
    await ClientRepository.instance
        .upsertLocal('c', {'clientName': 'Test', 'balance': 100.0});
    await BalanceHistoryRepository.instance.upsertLocal(BalanceHistoryLocal(
      id: 'sale',
      parentId: 'c',
      parentType: 'client',
      type: 'sale',
      enteredBalance: 100,
      timestamp: DateTime(2026, 1, 1),
    ));

    await ClientRepository.instance.mergeCloud('c', {
      '_deleted': true,
      '_version': 1,
      'updatedAt': DateTime(2026, 1, 2),
    });

    expect(ClientRepository.instance.getById('c'), isNull);
    expect(BalanceHistoryRepository.instance.getForClient('c'), hasLength(1));
  });
}
