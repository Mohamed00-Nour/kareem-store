import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/supplier_balance_store.dart';
import 'package:kareem_store/Services/supplier_operation_service.dart';
import 'package:kareem_store/Services/supplier_invoice_running_balance_service.dart';
import 'package:kareem_store/Services/invoice_footer_data.dart';
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
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/sync/batch_sync_engine.dart';
import 'package:kareem_store/sync/cloud_snapshot_guard.dart';
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

  Future<void> downloadPurchaseOnAnotherDevice(String? copyOperation) async {
    const root = 'buying invoices/purchase-1';
    const copy = 'suppliers/supplier-1/buying invoices/purchase-1';
    await appMetaBox.delete(CloudSnapshotGuard.operationKey(root));
    await appMetaBox.delete(CloudSnapshotGuard.versionKey(root));
    await appMetaBox.delete(CloudSnapshotGuard.operationKey(copy));
    if (copyOperation != null) {
      await appMetaBox.put(
          CloudSnapshotGuard.operationKey(copy), copyOperation);
    }
    await InvoiceRepository.instance
        .mergeCloudBuying('purchase-1', cloud.documents[root]!);
  }

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

  test(
      'purchase detail uses chronological supplier footer after payments and edits',
      () async {
    final supplierId = await SupplierOperationService.createSupplier(
        name: 'Footer supplier', openingBalance: 40);
    final first = {
      ...purchase(),
      'supplierId': supplierId,
      'supplierName': 'Footer supplier',
      'date': DateTime.now().add(const Duration(days: 1)),
      'invoiceDiscount': 10.0,
    };
    final second = {
      ...purchase(total: 200, paid: 50),
      'id': 'purchase-2',
      'supplierId': supplierId,
      'supplierName': 'Footer supplier',
      'date': DateTime.now().add(const Duration(days: 3)),
    };
    await SupplierOperationService.saveBuyingInvoice(first);
    await SupplierOperationService.savePayment(
      supplierId: supplierId,
      direction: 'عليه',
      amount: 10,
      description: 'Between invoices',
      date: DateTime.now().add(const Duration(days: 2)),
      paymentMethod: 'cash',
      voucherNumber: 1,
    );
    await SupplierOperationService.saveBuyingInvoice(second);
    await SupplierOperationService.savePayment(
      supplierId: supplierId,
      direction: 'عليه',
      amount: 30,
      description: 'After invoices',
      date: DateTime.now().add(const Duration(days: 4)),
      paymentMethod: 'cash',
      voucherNumber: 2,
    );
    expect(SupplierBalanceStore.balance(supplierId), 230);
    final initial = InvoiceFooterData.fromInvoice(
        SupplierInvoiceRunningBalanceService.buildPayload(second));
    expect(initial.previous, 110);
    expect(initial.remaining, 260);
    // An earlier edit must also update the later invoice's previous balance.
    await SupplierOperationService.saveBuyingInvoice(
        {...first, 'totalSum': 150.0},
        editing: true);
    final firstFooter = InvoiceFooterData.fromInvoice(
        SupplierInvoiceRunningBalanceService.buildPayload(first));
    final secondFooter = InvoiceFooterData.fromInvoice(
        SupplierInvoiceRunningBalanceService.buildPayload(second));
    expect(firstFooter.previous, 40);
    expect(firstFooter.total, 150);
    expect(firstFooter.discount, 10);
    expect(firstFooter.remaining, 170);
    expect(secondFooter.previous, 160);
    expect(secondFooter.total, 200);
    expect(secondFooter.paid, 50);
    expect(secondFooter.remaining, 310);
    expect(SupplierBalanceStore.balance(supplierId), 280);
    // Equal display numbers must not select the other invoice.
    expect(firstFooter.total, isNot(secondFooter.total));
    final nameOnly = SupplierInvoiceRunningBalanceService.buildPayload({
      ...second,
      'supplierId': '',
      'previousBalance': -999.0,
      'currentSupplierBalance': 999.0,
    });
    expect(InvoiceFooterData.fromInvoice(nameOnly).rows, secondFooter.rows);
  });

  test('supplier footer calculation includes returns and signed vouchers', () {
    final purchaseInvoice = {
      'supplierName': 'Fixture supplier',
      'date': DateTime(2026, 10, 12, 13),
      'totalSum': 100.0,
      'paidAmount': 20.0,
    };
    final returned = {
      'supplierName': 'Fixture supplier',
      'date': DateTime(2026, 10, 12, 11),
      'totalSum': 20.0,
      'paidAmount': 5.0,
    };
    SupplierInvoiceRunningBalanceService.apply(
      invoices: [purchaseInvoice],
      returns: [returned],
      payments: [
        {
          'timestamp': DateTime(2026, 10, 12, 9),
          'type': 'opening',
          'enteredBalance': 50.0,
          'direction': 'له',
        },
        {
          'timestamp': DateTime(2026, 10, 12, 10),
          'type': 'voucher',
          'enteredBalance': 10.0,
          'direction': 'عليه',
        },
        {
          'timestamp': DateTime(2026, 10, 12, 12),
          'type': 'voucher',
          'enteredBalance': 30.0,
          'direction': 'له',
        },
      ],
    );
    expect(InvoiceFooterData.fromInvoice(returned).previous, 40);
    expect(InvoiceFooterData.fromInvoice(returned).remaining, 25);
    expect(InvoiceFooterData.fromInvoice(purchaseInvoice).previous, 55);
    expect(InvoiceFooterData.fromInvoice(purchaseInvoice).remaining, 135);
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

  for (final copyOperation in <String?>[null, 'stale-copy-operation']) {
    test(
        'purchase edit uses the main invoice with copy metadata $copyOperation',
        () async {
      await SupplierOperationService.saveBuyingInvoice(purchase());
      await drain();
      await downloadPurchaseOnAnotherDevice(copyOperation);

      await SupplierOperationService.saveBuyingInvoice(
          purchase(total: 180, paid: 30, quantity: 3),
          editing: true);
      await drain();
      await drain();

      expect(syncQueueBox.isEmpty, isTrue);
      expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 200);
      expect(cloud.documents['products/product-1']!['quantity'], 13);
      expect(cloud.documents['box/mainBox']!['value'], 970);
      expect(cloud.documents['suppliers/supplier-1/buying invoices/purchase-1'],
          cloud.documents['buying invoices/purchase-1']);
    });
  }

  test('previously failed purchase copy conflict recovers the stored operation',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    await downloadPurchaseOnAnotherDevice(null);
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);
    final item = syncQueueBox.values.single;
    final payloadBeforeRetry = item.payloadJson;
    await SyncQueueManager.instance.markFailed(
        item.operationId,
        StateError('Concurrent change to '
            'suppliers/supplier-1/buying invoices/purchase-1; '
            'review before retrying'));
    item.retryCount = 5;
    await item.save();

    await drain();
    await drain();

    expect(syncQueueBox.isEmpty, isTrue);
    expect(item.payloadJson, payloadBeforeRetry);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 200);
    expect(cloud.documents['products/product-1']!['quantity'], 13);
    expect(cloud.documents['box/mainBox']!['value'], 970);
  });

  test('purchase edit still rejects a changed main invoice', () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    await downloadPurchaseOnAnotherDevice(null);
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);
    cloud.documents['buying invoices/purchase-1']!['_operationId'] =
        'another-device-edit';

    await drain();
    await drain();

    final item = syncQueueBox.values.single;
    expect(item.status, 'failed');
    expect(item.lastError, contains('Concurrent change to buying invoices/'));
    expect(SyncQueueManager.instance.canRetryAutomatically(item), isFalse);
    expect(item.retryCount, 1);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 130);
    expect(cloud.documents['products/product-1']!['quantity'], 12);
    expect(cloud.documents['box/mainBox']!['value'], 980);
  });

  test('purchase edit rejects changed financial fields on the main invoice',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    await downloadPurchaseOnAnotherDevice(null);
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);
    cloud.documents['buying invoices/purchase-1']!['totalSum'] = 150.0;

    await drain();

    final item = syncQueueBox.values.single;
    expect(item.status, 'failed');
    expect(item.lastError,
        contains('Invoice lines or customer changed: buying invoices/'));
    expect(cloud.documents['buying invoices/purchase-1']!['totalSum'], 150);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 130);
    expect(cloud.documents['products/product-1']!['quantity'], 12);
    expect(cloud.documents['box/mainBox']!['value'], 980);
  });

  test('purchase edit restores a missing supplier copy from the main invoice',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    cloud.documents.remove('suppliers/supplier-1/buying invoices/purchase-1');
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);
    await drain();

    expect(syncQueueBox.isEmpty, isTrue);
    expect(cloud.documents['suppliers/supplier-1/buying invoices/purchase-1'],
        cloud.documents['buying invoices/purchase-1']);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], 200);
  });

  test('independent paid purchase continues after a different invoice conflict',
      () async {
    await SupplierOperationService.saveBuyingInvoice(purchase());
    await drain();
    await SupplierOperationService.saveBuyingInvoice(
        purchase(total: 180, paid: 30, quantity: 3),
        editing: true);
    final blockedId = syncQueueBox.values.single.operationId;
    cloud.documents['buying invoices/purchase-1']!['_operationId'] =
        'another-device-edit';

    await suppliersBox.put(
        'supplier-2',
        SupplierLocal(
            id: 'supplier-2',
            name: 'Second supplier',
            balance: 0,
            updatedAt: DateTime(2026, 9, 1)));
    await productsBox.put(
        'product-2',
        ProductLocal(
            id: 'product-2',
            name: 'Second product',
            quantity: 10,
            costPrice: 5,
            updatedAt: DateTime(2026, 9, 1)));
    await SupplierBalanceStore.preserveExistingBalances();
    cloud.documents['suppliers/supplier-2'] =
        SupplierOperationService.supplierMap('supplier-2');
    cloud.documents['products/product-2'] =
        productsBox.get('product-2')!.toMap();
    await SupplierOperationService.saveBuyingInvoice({
      ...purchase(total: 60, paid: 10, quantity: 1),
      'id': 'purchase-2',
      'supplierId': 'supplier-2',
      'products': [
        {
          'id': 'product-2',
          'product': 'Second product',
          'amount': 1.0,
          'cost': 60.0,
          'totalCost': 60.0,
          'newCostPrice': 60.0
        }
      ],
    });

    await drain();

    expect(syncQueueBox.length, 1);
    expect(syncQueueBox.get(blockedId)!.status, 'failed');
    expect(cloud.documents['buying invoices/purchase-1']!['totalSum'], 100);
    expect(cloud.documents['buying invoices/purchase-2']!['totalSum'], 60);
    expect(cloud.documents['suppliers/supplier-2']!['totalBalance'], 50);
    expect(cloud.documents['products/product-2']!['quantity'], 11);
    expect(cloud.documents['box/mainBox']!['value'], 970);
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
