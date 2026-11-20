import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/invoice_footer_data.dart';
import 'package:kareem_store/Services/invoice_number_utils.dart';
import 'package:kareem_store/Services/supplier_balance_store.dart';
import 'package:kareem_store/Services/supplier_invoice_running_balance_service.dart';
import 'package:kareem_store/Services/supplier_operation_service.dart';
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
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/sync/batch_sync_engine.dart';
import 'package:kareem_store/sync/cloud_snapshot_guard.dart';
import 'package:kareem_store/sync/financial_cloud_store.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';

class _MemoryCloud extends FinancialCloudStore {
  Map<String, Map<String, dynamic>> documents = {};

  @override
  Future<Map<String, dynamic>> transaction(
      Future<Map<String, dynamic>> Function(FinancialTransaction tx)
          action) async {
    final tx = _MemoryTransaction(documents);
    final result = await action(tx);
    documents = {...documents, ...tx.writes};
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

  const root = 'returnBuyingInvoices/return-1';
  const copy = 'suppliers/supplier-1/returnBuyingInvoices/return-1';

  /// Supplier starts at 50 payable, product at 10 units (cost 5), cash 1000.
  Map<String, dynamic> purchaseReturn(
          {double quantity = 3, double price = 10, double refund = 10}) =>
      {
        'id': 'return-1',
        'invoiceNumber': 4,
        'supplierId': 'supplier-1',
        'supplierName': 'Fixture supplier',
        'date': DateTime(2026, 11, 20),
        'totalSum': quantity * price,
        'paidAmount': refund,
        'products': [
          {
            'id': 'product-1',
            'product': 'Fixture product',
            'amount': quantity,
            'cost': price,
            'totalCost': quantity * price,
          }
        ],
      };

  Future<void> drain() => BatchSyncEngine.forTesting(cloud).processQueue();

  void expectEverywhere(double balance, double stock, double cash) {
    expect(SupplierBalanceStore.balance('supplier-1'), balance);
    expect(suppliersBox.get('supplier-1')!.balance, balance);
    expect(productsBox.get('product-1')!.quantity, stock);
    expect(boxCacheBox.get('mainBox')!.value, cash);
    expect(cloud.documents['suppliers/supplier-1']!['totalBalance'], balance);
    expect(cloud.documents['products/product-1']!['quantity'], stock);
    expect(cloud.documents['box/mainBox']!['value'], cash);
  }

  /// Another admin's edit of return-1 (3×10, refund 10 → 5×10, refund 20)
  /// reaches the cloud first: payable 30 → 20, stock 7 → 5, cash 1010 → 1020.
  Future<void> anotherAdminEditsReturn() async {
    final remote = {
      ...purchaseReturn(quantity: 5, refund: 20),
      'invoiceId': 'return-1',
      'invoiceType': 'buying_return',
      '_deleted': false,
      '_version': (cloud.documents[root]!['_version'] as num).toInt() + 1,
      '_operationId': 'remote-edit',
    };
    cloud.documents[root] = remote;
    cloud.documents[copy] = Map<String, dynamic>.from(remote);
    cloud.documents['suppliers/supplier-1'] = {
      ...cloud.documents['suppliers/supplier-1']!,
      'balance': 20.0,
      'totalBalance': 20.0,
    };
    cloud.documents['products/product-1'] = {
      ...cloud.documents['products/product-1']!,
      'quantity': 5.0,
    };
    cloud.documents['box/mainBox'] = {
      ...cloud.documents['box/mainBox']!,
      'value': 1020.0,
    };
    final event = {
      'supplierId': 'supplier-1',
      'operationId': 'remote-edit',
      'delta': -10.0,
      'description': 'Remote purchase return edit',
      'timestamp': DateTime(2026, 11, 20, 12),
    };
    cloud.documents['suppliers/supplier-1/financialOperations/remote-edit'] =
        event;
    // The live receipt feed delivers the other device's balance event.
    await SupplierBalanceStore.importEvent('supplier-1', 'remote-edit', event);
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('purchase_return_');
    Hive.init(directory.path);
    Hive.registerAdapter(ClientLocalAdapter());
    Hive.registerAdapter(SupplierLocalAdapter());
    Hive.registerAdapter(ProductLocalAdapter());
    Hive.registerAdapter(InvoiceLocalAdapter());
    Hive.registerAdapter(BalanceHistoryLocalAdapter());
    Hive.registerAdapter(BoxLocalAdapter());
    Hive.registerAdapter(QuoteLocalAdapter());
    Hive.registerAdapter(SyncQueueItemAdapter());
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
            updatedAt: DateTime(2026, 11, 1)));
    await productsBox.put(
        'product-1',
        ProductLocal(
            id: 'product-1',
            name: 'Fixture product',
            quantity: 10,
            costPrice: 5,
            sellingPrice1: 8,
            updatedAt: DateTime(2026, 11, 1)));
    await boxCacheBox.put('mainBox',
        BoxLocal(id: 'mainBox', value: 1000, updatedAt: DateTime(2026, 11, 1)));
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

  test('offline return lowers payable and stock and adds the refund to cash',
      () async {
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());

    // Payable 50 − (30 − 10) = 30; stock 10 − 3; cash 1000 + 10.
    expect(SupplierBalanceStore.balance('supplier-1'), 30);
    expect(suppliersBox.get('supplier-1')!.balance, 30);
    expect(productsBox.get('product-1')!.quantity, 7);
    expect(boxCacheBox.get('mainBox')!.value, 1010);
    // A return never changes product prices.
    expect(productsBox.get('product-1')!.costPrice, 5);
    expect(productsBox.get('product-1')!.sellingPrice1, 8);

    final saved = buyingReturnInvoicesBox.get('return-1')!;
    expect(saved.invoiceType, 'buying_return');
    expect(saved.previousBalance, 50);
    expect(syncQueueBox.length, 1);
    expect(syncQueueBox.values.single.operationType, 'createBuyingReturn');

    final history =
        BalanceHistoryRepository.instance.getForSupplier('supplier-1');
    expect(history.map((entry) => entry.type),
        containsAll(['buying_return', 'buying_return_payment']));
  });

  test('return uploads the invoice, its copy and every effect exactly once',
      () async {
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());
    await drain();
    await drain();

    expect(syncQueueBox.isEmpty, isTrue);
    expectEverywhere(30, 7, 1010);
    expect(cloud.documents[root]!['invoiceType'], 'buying_return');
    expect(cloud.documents[copy]!['totalSum'], 30);
    expect(
        cloud.documents.containsKey(
            'suppliers/supplier-1/balanceHistory/return-1_buying_return'),
        isTrue);
    expect(
        cloud.documents.containsKey(
            'suppliers/supplier-1/balanceHistory/return-1_buying_return_pay'),
        isTrue);
    expect(
        cloud.documents.keys.where((path) =>
            path.startsWith('suppliers/supplier-1/financialOperations/')),
        hasLength(1));
    expect(buyingReturnInvoicesBox.containsKey('return-1'), isTrue);
  });

  test('return edit and deletion apply only their differences', () async {
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());
    await drain();

    await SupplierOperationService.saveBuyingReturn(
        purchaseReturn(quantity: 5, refund: 0),
        editing: true);
    // Payable 50 − 50 = 0; stock 10 − 5; refund removed from cash.
    expect(syncQueueBox.values.single.operationType, 'editBuyingReturn');
    await drain();
    expectEverywhere(0, 5, 1000);
    expect(
        cloud.documents.containsKey(
                'suppliers/supplier-1/balanceHistory/return-1_buying_return_pay') &&
            cloud.documents[
                        'suppliers/supplier-1/balanceHistory/return-1_buying_return_pay']![
                    '_deleted'] !=
                true,
        isFalse);

    await SupplierOperationService.deleteBuyingReturn('return-1');
    expect(buyingReturnInvoicesBox.containsKey('return-1'), isFalse);
    await drain();
    expectEverywhere(50, 10, 1000);
    expect(cloud.documents[root]!['_deleted'], isTrue);
    expect(cloud.documents[copy]!['_deleted'], isTrue);
  });

  test('refund larger than the return total is rejected without effects',
      () async {
    await expectLater(
      SupplierOperationService.saveBuyingReturn(
          purchaseReturn(quantity: 1, refund: 20)),
      throwsArgumentError,
    );
    expect(syncQueueBox.isEmpty, isTrue);
    expect(buyingReturnInvoicesBox.isEmpty, isTrue);
    expect(SupplierBalanceStore.balance('supplier-1'), 50);
    expect(productsBox.get('product-1')!.quantity, 10);
    expect(boxCacheBox.get('mainBox')!.value, 1000);
  });

  test('returning more than the stock on hand is allowed', () async {
    await SupplierOperationService.saveBuyingReturn(
        purchaseReturn(quantity: 12, refund: 0));
    expect(productsBox.get('product-1')!.quantity, -2);
    expect(SupplierBalanceStore.balance('supplier-1'), -70);
  });

  test('another device imports the uploaded return into its ledger', () async {
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());
    await drain();
    await buyingReturnInvoicesBox.clear();
    await appMetaBox.delete(CloudSnapshotGuard.versionKey(root));
    await appMetaBox.delete(CloudSnapshotGuard.operationKey(root));

    await InvoiceRepository.instance
        .mergeCloudBuyingReturnRoot('return-1', cloud.documents[root]);

    final returns =
        InvoiceRepository.instance.getBuyingReturnsBySupplier('supplier-1');
    expect(returns, hasLength(1));
    expect(returns.single.totalSum, 30);
    expect(InvoiceRepository.instance.getAllBuyingReturns(), hasLength(1));

    // A delete tombstone from the other device removes it again.
    await InvoiceRepository.instance.mergeCloudBuyingReturnRoot('return-1', {
      ...cloud.documents[root]!,
      '_deleted': true,
      '_version': (cloud.documents[root]!['_version'] as num).toInt() + 1,
    });
    expect(buyingReturnInvoicesBox.containsKey('return-1'), isFalse);
  });

  test('return footer shows the balance before and after the return', () async {
    final saved =
        await SupplierOperationService.saveBuyingReturn(purchaseReturn());
    final footer = InvoiceFooterData.fromInvoice(
        SupplierInvoiceRunningBalanceService.buildPayload(saved));
    expect(footer.total, 30);
    expect(footer.remaining, footer.previous - 20);
  });

  test('purchase returns have their own invoice numbers', () async {
    await buyingInvoicesBox.put(
        'purchase-9',
        InvoiceLocal(
            id: 'purchase-9',
            invoiceNumber: 9,
            supplierId: 'supplier-1',
            date: DateTime(2026, 11, 1),
            invoiceType: 'buying',
            updatedAt: DateTime(2026, 11, 1)));
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());

    expect(LocalInvoiceCounter.peekNextNumber('buying_return'), 5);
    expect(LocalInvoiceCounter.peekNextNumber('buying'), 10);
  });

  test('return deletion rebases on the latest version from another device',
      () async {
    await SupplierOperationService.saveBuyingReturn(purchaseReturn());
    await drain();
    await SupplierOperationService.deleteBuyingReturn('return-1');
    final deleteId = syncQueueBox.values.single.operationId;
    expect(SupplierBalanceStore.balance('supplier-1'), 50);

    await anotherAdminEditsReturn();
    await drain();

    // The delete reverses the latest 5×10 / refund 20 version: +30 payable.
    expect(syncQueueBox.isEmpty, isTrue);
    expect(cloud.documents[root]!['_deleted'], isTrue);
    expect(
        cloud.documents['suppliers/supplier-1/financialOperations/$deleteId']![
            'delta'],
        30);
    expectEverywhere(50, 10, 1000);
  });

  group('two admins edit the same purchase return', () {
    Future<SyncQueueItem> conflictedEdit() async {
      await SupplierOperationService.saveBuyingReturn(purchaseReturn());
      await drain();
      await anotherAdminEditsReturn();
      // This admin edits the stale copy: 4×10, refund 0.
      await SupplierOperationService.saveBuyingReturn(
          purchaseReturn(quantity: 4, refund: 0),
          editing: true);
      await drain();
      final item = syncQueueBox.values.single;
      expect(item.status, 'failed');
      expect(SyncQueueManager.instance.canResolveInvoiceEditConflict(item),
          isTrue);
      return item;
    }

    test('keeping my edit applies it on top of the latest version', () async {
      final item = await conflictedEdit();
      await SyncQueueManager.instance
          .resolveInvoiceEditConflict(item.operationId, keepMine: true);
      await drain();

      expect(syncQueueBox.isEmpty, isTrue);
      expect(cloud.documents[root]!['totalSum'], 40);
      // From 5×10 / refund 20 to 4×10 / refund 0: payable 50 − 40 = 10,
      // stock +1 → 6, cash −20 → 1000.
      expectEverywhere(10, 6, 1000);
      expect(buyingReturnInvoicesBox.get('return-1')!.totalSum, 40);
    });

    test('discarding my edit keeps the other admin version', () async {
      final item = await conflictedEdit();
      await SyncQueueManager.instance
          .resolveInvoiceEditConflict(item.operationId, keepMine: false);
      await drain();

      expect(syncQueueBox.isEmpty, isTrue);
      expect(cloud.documents[root]!['totalSum'], 50);
      expectEverywhere(20, 5, 1020);
      expect(buyingReturnInvoicesBox.get('return-1')!.totalSum, 50);
    });
  });
}
