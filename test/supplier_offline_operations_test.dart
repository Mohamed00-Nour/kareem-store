import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/supplier_balance_store.dart';
import 'package:kareem_store/Services/supplier_operation_service.dart';
import 'package:kareem_store/Services/invoice_print_service.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/box_local.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/product_local.dart';
import 'package:kareem_store/local_db/models/quote_local.dart';
import 'package:kareem_store/local_db/models/supplier_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/repositories/supplier_repository.dart';
import 'package:kareem_store/repositories/product_repository.dart';
import 'package:kareem_store/sync/batch_sync_engine.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';
import 'package:kareem_store/sync/financial_cloud_store.dart';

class _MemoryCloud extends FinancialCloudStore {
  Map<String, Map<String, dynamic>> documents = {};
  bool loseAcknowledgement = false;
  int failuresBeforeCommit = 0;

  @override
  Future<Map<String, dynamic>> transaction(
      Future<Map<String, dynamic>> Function(FinancialTransaction tx)
          action) async {
    if (failuresBeforeCommit > 0) {
      failuresBeforeCommit--;
      throw StateError('test network unavailable');
    }
    final tx = _MemoryTransaction(documents);
    final result = await action(tx);
    documents = {...documents, ...tx.writes};
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw StateError('test acknowledgement lost');
    }
    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
          String id) async =>
      const {};

  @override
  Future<Map<String, Map<String, dynamic>>> readSupplierEvents(
          String id) async =>
      {
        for (final entry in documents.entries)
          if (entry.key.startsWith('suppliers/$id/financialOperations/'))
            entry.key.split('/').last: entry.value,
      };
}

class _MemoryTransaction implements FinancialTransaction {
  final Map<String, Map<String, dynamic>> before;
  final Map<String, Map<String, dynamic>> writes = {};
  _MemoryTransaction(this.before);

  @override
  Future<Map<String, dynamic>?> read(String path) async {
    if (writes.isNotEmpty) throw StateError('read after write');
    final value = before[path];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  void write(String path, Map<String, dynamic> data) => writes[path] = data;
}

void main() {
  late Directory directory;
  late _MemoryCloud cloud;

  Future<void> openBoxes() async {
    await Hive.openBox<ClientLocal>(HiveBoxNames.clients);
    await Hive.openBox<SupplierLocal>(HiveBoxNames.suppliers);
    await Hive.openBox<ProductLocal>(HiveBoxNames.products);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.invoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.returnInvoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingInvoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingReturnInvoices);
    await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
    await Hive.openBox<BoxLocal>(HiveBoxNames.box);
    await Hive.openBox<QuoteLocal>(HiveBoxNames.quotes);
    await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
    await Hive.openBox(HiveBoxNames.appMeta);
  }

  Map<String, dynamic> purchase(
          {double total = 100, double paid = 20, double quantity = 2}) =>
      {
        'id': 'purchase-1',
        'invoiceNumber': 7,
        'supplierId': 'supplier-1',
        'supplierName': 'Fixture supplier',
        'date': DateTime(2026, 9, 28),
        'totalSum': total,
        'paidAmount': paid,
        'products': [
          {
            'id': 'product-1',
            'product': 'Fixture product',
            'amount': quantity,
            'cost': total / quantity,
            'totalCost': total,
            'newCostPrice': total / quantity,
          }
        ],
      };

  Future<void> drain() => BatchSyncEngine.forTesting(cloud).processQueue();

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('supplier_offline_');
    Hive.init(directory.path);
    Hive.registerAdapter(ClientLocalAdapter());
    Hive.registerAdapter(SupplierLocalAdapter());
    Hive.registerAdapter(ProductLocalAdapter());
    Hive.registerAdapter(InvoiceLocalAdapter());
    Hive.registerAdapter(BalanceHistoryLocalAdapter());
    Hive.registerAdapter(BoxLocalAdapter());
    Hive.registerAdapter(QuoteLocalAdapter());
    Hive.registerAdapter(SyncQueueItemAdapter());
    await openBoxes();
  });

  setUp(() async {
    for (final box in [
      clientsBox,
      suppliersBox,
      productsBox,
      invoicesBox,
      returnInvoicesBox,
      buyingInvoicesBox,
      buyingReturnInvoicesBox,
      balanceHistoryBox,
      boxCacheBox,
      quotesBox,
      syncQueueBox,
      appMetaBox,
    ]) {
      await box.clear();
    }
    await suppliersBox.put(
        'supplier-1',
        SupplierLocal(
            id: 'supplier-1',
            name: 'Fixture supplier',
            balance: 50,
            updatedAt: DateTime(2026, 9, 1)));
    await productsBox.put(
        'product-1',
        ProductLocal(
            id: 'product-1',
            name: 'Fixture product',
            quantity: 10,
            costPrice: 5,
            updatedAt: DateTime(2026, 9, 1)));
    await boxCacheBox.put('mainBox',
        BoxLocal(id: 'mainBox', value: 1000, updatedAt: DateTime(2026, 9, 1)));
    await SupplierBalanceStore.preserveExistingBalances();
    cloud = _MemoryCloud()
      ..documents = {
        'suppliers/supplier-1':
            SupplierOperationService.supplierMap('supplier-1'),
        'products/product-1': productsBox.get('product-1')!.toMap(),
        'box/mainBox': boxCacheBox.get('mainBox')!.toMap(),
      };
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('offline purchase updates payable, stock and cash before upload',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());

    expect(SupplierBalanceStore.balance('supplier-1'), 130);
    expect(suppliersBox.get('supplier-1')!.balance, 130);
    expect(productsBox.get('product-1')!.quantity, 12);
    expect(productsBox.get('product-1')!.costPrice, 50);
    expect(boxCacheBox.get('mainBox')!.value, 980);
    expect(syncQueueBox.length, 1);
    expect(buyingInvoicesBox.containsKey('purchase-1'), isTrue);
  });

  test('renamed purchase line resolves stock by immutable product id',
      () async {
    final renamedPurchase = purchase();
    final line =
        (renamedPurchase['products'] as List).single as Map<String, dynamic>;
    line['product'] = 'Renamed invoice product';
    line['id'] = '';
    line['productId'] = 'product-1';

    await SupplierOperationService.saveBuyingInvoice(renamedPurchase);

    expect(productsBox.get('product-1')!.quantity, 12);
    final savedLine = buyingInvoicesBox.get('purchase-1')!.products.single;
    expect(savedLine['product'], 'Renamed invoice product');
    expect(savedLine['productId'] ?? savedLine['id'], 'product-1');
  });

  test('offline product rename preserves fields and creates a durable upload',
      () async {
    final before = productsBox.get('product-1')!;
    final originalQuantity = before.quantity;
    final originalCost = before.costPrice;

    await ProductRepository.instance.renameLocalFirst(
      'product-1',
      'Renamed locally',
    );

    final renamed = productsBox.get('product-1')!;
    expect(renamed.name, 'Renamed locally');
    expect(renamed.quantity, originalQuantity);
    expect(renamed.costPrice, originalCost);
    expect(syncQueueBox.length, 1);
    final pending = syncQueueBox.values.single;
    expect(pending.operationType, 'editProduct');
    final payload = SyncQueueManager.decodePayload(pending);
    expect(payload['productId'], 'product-1');
    expect((payload['data'] as Map)['name'], 'Renamed locally');
  });

  test('Firestore timestamps in supplier events are converted before Hive save',
      () async {
    final timestamp = Timestamp.fromDate(DateTime(2026, 9, 28, 23, 22));
    await SupplierBalanceStore.importEvent('supplier-1', 'timestamp-event', {
      'delta': 5.0,
      'appliedAt': timestamp,
    });

    final saved = appMetaBox.get(
        SupplierBalanceStore.eventKey('supplier-1', 'timestamp-event')) as Map;
    expect(saved['appliedAt'], isA<DateTime>());
    expect(SupplierBalanceStore.balance('supplier-1'), 55);
  });

  test('pending purchase rejects an older supplier cloud snapshot', () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());

    await SupplierRepository.instance.mergeCloud('supplier-1', {
      'id': 'supplier-1',
      'name': 'Fixture supplier',
      'totalBalance': 50.0,
      'balance': 50.0,
      '_version': 0,
    });

    expect(SupplierBalanceStore.balance('supplier-1'), 130);
    expect(suppliersBox.get('supplier-1')!.balance, 130);
  });

  test('supplier creation and opening balance are one durable operation',
      () async {
    final id = await SupplierOperationService.createSupplier(
      name: 'New supplier',
      openingBalance: 40,
    );

    expect(SupplierBalanceStore.balance(id), 40);
    expect(suppliersBox.get(id)!.balance, 40);
    expect(syncQueueBox.length, 1);
    await drain();
    await drain();

    expect(cloud.documents['suppliers/$id']!['totalBalance'], 40);
    expect(
        cloud.documents.keys.where(
            (path) => path.startsWith('suppliers/$id/financialOperations/')),
        hasLength(1));
    expect(
        cloud.documents.containsKey('supplier_vouchers/${id}_opening'), isTrue);
    expect(boxCacheBox.get('mainBox')!.value, 1000);
  });

  test('equal display numbers do not merge different purchase invoices',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await SupplierOperationService.saveBuyingInvoice({
      ...purchase(total: 60, paid: 10, quantity: 1),
      'id': 'purchase-2',
    });

    final purchaseRows = BalanceHistoryRepository.instance
        .getForSupplier('supplier-1')
        .where((entry) => entry.type == 'buying')
        .toList();
    expect(purchaseRows, hasLength(2));
    expect(purchaseRows.map((entry) => entry.invoiceId).toSet(),
        {'purchase-1', 'purchase-2'});
  });

  test('restart and lost acknowledgement cannot apply purchase twice',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await Hive.close();
    await openBoxes();
    cloud.loseAcknowledgement = true;
    await drain();
    expect(syncQueueBox.length, 1);
    await Hive.close();
    await openBoxes();
    await SyncQueueManager.instance.resetFailedItems();
    await drain();

    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 130);
    expect(cloud.documents['products/product-1']!['quantity'], 12);
    expect(cloud.documents['box/mainBox']!['value'], 980);
    expect(syncQueueBox.isEmpty, isTrue);
  });

  test('failed upload remains visible and reconnect applies it once', () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    cloud.failuresBeforeCommit = 1;

    await drain();
    expect(syncQueueBox.length, 1);
    expect(syncQueueBox.values.single.status, 'failed');
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 50);

    await SyncQueueManager.instance.resetFailedItems();
    await drain();
    expect(syncQueueBox.isEmpty, isTrue);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 130);
    expect(cloud.documents['products/product-1']!['quantity'], 12);
    expect(cloud.documents['box/mainBox']!['value'], 980);
  });

  test('purchase edit and deletion apply only their differences', () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);

    expect(SupplierBalanceStore.balance('supplier-1'), 200);
    expect(productsBox.get('product-1')!.quantity, 13);
    expect(boxCacheBox.get('mainBox')!.value, 970);
    await drain();
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 200);
    expect(cloud.documents['products/product-1']!['quantity'], 13);
    expect(cloud.documents['box/mainBox']!['value'], 970);

    await SupplierOperationService.deleteBuyingInvoice('purchase-1');
    expect(SupplierBalanceStore.balance('supplier-1'), 50);
    expect(productsBox.get('product-1')!.quantity, 10);
    expect(boxCacheBox.get('mainBox')!.value, 1000);
    await drain();
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 50);
    expect(cloud.documents['products/product-1']!['quantity'], 10);
    expect(cloud.documents['box/mainBox']!['value'], 1000);
  });

  test('purchase deletion rebases safely when another device edited it',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();

    // This device deletes the version it currently has. The local response is
    // immediate, while its upload remains queued.
    await SupplierOperationService.deleteBuyingInvoice('purchase-1');
    final deleteOperationId = syncQueueBox.values.single.operationId;
    expect(SupplierBalanceStore.balance('supplier-1'), 50);
    expect(productsBox.get('product-1')!.quantity, 10);
    expect(boxCacheBox.get('mainBox')!.value, 1000);

    // Before that upload reaches the server, another device edits the same
    // invoice from 100/20/2 to 180/30/3.
    final remoteInvoice = {
      ...purchase(total: 180, paid: 30, quantity: 3),
      '_deleted': false,
      '_version':
          (cloud.documents['buying invoices/purchase-1']!['_version'] as num)
                  .toInt() +
              1,
      '_operationId': 'remote-edit',
    };
    cloud.documents['buying invoices/purchase-1'] = remoteInvoice;
    cloud.documents['suppliers/supplier-1/buying invoices/purchase-1'] =
        Map<String, dynamic>.from(remoteInvoice);
    cloud.documents['suppliers/supplier-1'] = {
      ...cloud.documents['suppliers/supplier-1']!,
      'balance': 200.0,
      'totalBalance': 200.0,
      '_version': (cloud.documents['suppliers/supplier-1']!['_version'] as num)
              .toInt() +
          1,
      '_operationId': 'remote-edit',
    };
    cloud.documents['products/product-1'] = {
      ...cloud.documents['products/product-1']!,
      'quantity': 13.0,
      '_version':
          (cloud.documents['products/product-1']!['_version'] as num).toInt() +
              1,
      '_operationId': 'remote-edit',
    };
    cloud.documents['box/mainBox'] = {
      ...cloud.documents['box/mainBox']!,
      'value': 970.0,
      '_version':
          (cloud.documents['box/mainBox']!['_version'] as num).toInt() + 1,
      '_operationId': 'remote-edit',
    };
    final remoteEvent = {
      'supplierId': 'supplier-1',
      'operationId': 'remote-edit',
      'delta': 70.0,
      'description': 'Remote purchase edit',
      'timestamp': DateTime(2026, 9, 29),
    };
    cloud.documents['suppliers/supplier-1/financialOperations/remote-edit'] =
        remoteEvent;
    await SupplierBalanceStore.importEvent(
        'supplier-1', 'remote-edit', remoteEvent);

    expect(SupplierBalanceStore.balance('supplier-1'), 120);
    await drain();

    // The queued delete reverses the latest server version, then replaces its
    // provisional local -80 event with the acknowledged -150 event.
    expect(syncQueueBox.isEmpty, isTrue);
    expect(cloud.documents['buying invoices/purchase-1']!['_deleted'], isTrue);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 50);
    expect(cloud.documents['products/product-1']!['quantity'], 10);
    expect(cloud.documents['box/mainBox']!['value'], 1000);
    expect(
        cloud.documents[
                'suppliers/supplier-1/financialOperations/$deleteOperationId']![
            'delta'],
        -150);
    expect(SupplierBalanceStore.balance('supplier-1'), 50);
    expect(suppliersBox.get('supplier-1')!.balance, 50);
    expect(productsBox.get('product-1')!.quantity, 10);
    expect(boxCacheBox.get('mainBox')!.value, 1000);
    expect(buyingInvoicesBox.containsKey('purchase-1'), isFalse);
  });

  test('purchase printing uses the unsynced Hive edit', () async {
    final stale = purchase();
    await SupplierOperationService.saveBuyingInvoice(stale);
    await SupplierOperationService.saveBuyingInvoice(
      purchase(total: 180, paid: 30, quantity: 3),
      editing: true,
    );

    final printable = await InvoicePrintService.prepareForPrint(stale);

    expect(printable['totalSum'], 180);
    expect(printable['paidAmount'], 30);
    expect(
        double.parse(
            (printable['products'] as List).single['amount'].toString()),
        3);
    expect(printable['currentSupplierBalance'], 200);
    expect(cloud.documents.containsKey('buying invoices/purchase-1'), isFalse);
  });

  test('supplier voucher uploads debt and cash exactly once', () async {
    await SupplierOperationService.savePayment(
      supplierId: 'supplier-1',
      direction: 'عليه',
      amount: 20,
      description: 'Fixture payment',
      date: DateTime(2026, 9, 28),
      paymentMethod: 'نقداً',
      voucherNumber: 4,
    );
    await drain();
    await drain();

    expect(SupplierBalanceStore.balance('supplier-1'), 30);
    expect(boxCacheBox.get('mainBox')!.value, 980);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 30);
    expect(cloud.documents['box/mainBox']!['value'], 980);
    expect(
        cloud.documents.keys
            .where((path) => path.startsWith('supplier_vouchers/')),
        hasLength(1));
  });

  test('supplier credit voucher increases payable without changing cash',
      () async {
    await SupplierOperationService.savePayment(
      supplierId: 'supplier-1',
      direction: 'له',
      amount: 15,
      description: 'Fixture credit',
      date: DateTime(2026, 9, 28),
      paymentMethod: 'نقداً',
      voucherNumber: 5,
    );
    await drain();

    expect(SupplierBalanceStore.balance('supplier-1'), 65);
    expect(boxCacheBox.get('mainBox')!.value, 1000);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 65);
    expect(cloud.documents['box/mainBox']!['value'], 1000);
  });
}
