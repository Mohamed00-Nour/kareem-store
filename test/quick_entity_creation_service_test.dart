import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/quick_entity_creation_service.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/product_local.dart';
import 'package:kareem_store/local_db/models/supplier_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('quick_create_test_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(0))
      Hive.registerAdapter(ProductLocalAdapter());
    if (!Hive.isAdapterRegistered(1))
      Hive.registerAdapter(ClientLocalAdapter());
    if (!Hive.isAdapterRegistered(2))
      Hive.registerAdapter(SupplierLocalAdapter());
    if (!Hive.isAdapterRegistered(3))
      Hive.registerAdapter(SyncQueueItemAdapter());
    if (!Hive.isAdapterRegistered(4))
      Hive.registerAdapter(InvoiceLocalAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(BalanceHistoryLocalAdapter());
    }

    await Hive.openBox(HiveBoxNames.appMeta);
    await Hive.openBox<ProductLocal>(HiveBoxNames.products);
    await Hive.openBox<ClientLocal>(HiveBoxNames.clients);
    await Hive.openBox<SupplierLocal>(HiveBoxNames.suppliers);
    await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.invoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.returnInvoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingInvoices);
    await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
  });

  setUp(() async {
    await Future.wait([
      appMetaBox.clear(),
      productsBox.clear(),
      clientsBox.clear(),
      suppliersBox.clear(),
      syncQueueBox.clear(),
      invoicesBox.clear(),
      returnInvoicesBox.clear(),
      buyingInvoicesBox.clear(),
      balanceHistoryBox.clear(),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test(
      'client is saved with opening history before a create operation is queued',
      () async {
    final client = await QuickEntityCreationService.instance.createClient(
      name: '  Alice   Store  ',
      openingBalance: 125,
      phone: '201000000000',
    );

    expect(client.name, 'Alice Store');
    expect(clientsBox.get(client.id)?.balance, 125);

    final opening =
        balanceHistoryBox.get('client_${client.id}_${client.id}_opening');
    expect(opening, isNotNull);
    expect(opening!.enteredBalance, 125);
    expect(opening.type, 'opening');

    final queued = SyncQueueManager.instance.getPending().single;
    final payload = SyncQueueManager.decodePayload(queued);
    expect(queued.operationType, 'createClient');
    expect(payload['clientId'], client.id);
    expect(payload['openingHistoryId'], '${client.id}_opening');
  });

  test('normalized client names cannot be created twice', () async {
    await QuickEntityCreationService.instance.createClient(
      name: 'Alice Store',
    );

    expect(
      () => QuickEntityCreationService.instance.createClient(
        name: '  ALICE    STORE ',
      ),
      throwsA(isA<QuickCreateDuplicateException>()),
    );
    expect(clientsBox.length, 1);
    expect(syncQueueBox.length, 1);
  });

  test('supplier opening history and upload IDs are deterministic', () async {
    final supplier = await QuickEntityCreationService.instance.createSupplier(
      name: 'Main Supplier',
      openingBalance: 80,
    );

    final opening =
        balanceHistoryBox.get('supplier_${supplier.id}_${supplier.id}_opening');
    expect(opening, isNotNull);
    expect(opening!.direction, 'له');

    final payload = SyncQueueManager.decodePayload(
      SyncQueueManager.instance.getPending().single,
    );
    expect(payload['openingHistoryId'], '${supplier.id}_opening');
    expect(payload['openingVoucherId'], '${supplier.id}_opening');
  });

  test('product is available in Hive immediately and creation is queued',
      () async {
    final product = await QuickEntityCreationService.instance.createProduct(
      name: '  Steel   Pipe ',
      data: const {
        'quantity': 3.0,
        'costPrice': 10.0,
        'sellingPrice1': 12.0,
      },
    );

    expect(product.name, 'Steel Pipe');
    expect(productsBox.get(product.id)?.quantity, 3);
    final queued = SyncQueueManager.instance.getPending().single;
    expect(queued.operationType, 'createProduct');
    expect(SyncQueueManager.decodePayload(queued)['productId'], product.id);
  });
}
