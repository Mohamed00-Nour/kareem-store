import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:kareem_store/local_db/models/product_local.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/supplier_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/expense_local.dart';
import 'package:kareem_store/local_db/models/quote_local.dart';
import 'package:kareem_store/local_db/models/box_local.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/department_local.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/repositories/box_repository.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/Services/invoice_number_utils.dart';

/// Helper: initialise Hive in a temp directory for tests.
Future<void> initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('hive_test_');
  Hive.init(dir.path);
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductLocalAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ClientLocalAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SupplierLocalAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SyncQueueItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(InvoiceLocalAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(ExpenseLocalAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(QuoteLocalAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(BoxLocalAdapter());
  if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(BalanceHistoryLocalAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(DepartmentLocalAdapter());

  await Hive.openBox<ProductLocal>(HiveBoxNames.products);
  await Hive.openBox<ClientLocal>(HiveBoxNames.clients);
  await Hive.openBox<SupplierLocal>(HiveBoxNames.suppliers);
  await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
  await Hive.openBox(HiveBoxNames.appMeta);
  await Hive.openBox<InvoiceLocal>(HiveBoxNames.invoices);
  await Hive.openBox<InvoiceLocal>(HiveBoxNames.returnInvoices);
  await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingInvoices);
  await Hive.openBox<QuoteLocal>(HiveBoxNames.quotes);
  await Hive.openBox<ExpenseLocal>(HiveBoxNames.expenses);
  await Hive.openBox<BoxLocal>(HiveBoxNames.box);
  await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
  await Hive.openBox<DepartmentLocal>(HiveBoxNames.departments);
}

Future<void> closeTestHive() async {
  await Hive.close();
}

void main() {
  setUpAll(() async => await initTestHive());
  tearDownAll(() async => await closeTestHive());

  // ── ProductLocal model ──────────────────────────────────────────────────

  group('ProductLocal', () {
    test('fromFirestore correctly maps all fields', () {
      final data = {
        'name': 'تورنيدو',
        'sellingPrice1': 150.0,
        'sellingPrice2': 140.0,
        'sellingPrice3': 130.0,
        'quantity': 25.0,
        'costPrice': 100.0,
        'barcode': '123456',
        'description': 'وصف المنتج',
      };
      final product = ProductLocal.fromFirestore('prod001', data);

      expect(product.id, 'prod001');
      expect(product.name, 'تورنيدو');
      expect(product.sellingPrice1, 150.0);
      expect(product.quantity, 25.0);
      expect(product.costPrice, 100.0);
      expect(product.barcode, '123456');
    });

    test('fromFirestore handles missing optional fields gracefully', () {
      final product = ProductLocal.fromFirestore('prod002', {'name': 'منتج'});
      expect(product.sellingPrice1, 0.0);
      expect(product.quantity, 0.0);
      expect(product.barcode, '');
      expect(product.description, '');
    });

    test('ProductLocal can be stored and retrieved from Hive box', () async {
      final box = Hive.box<ProductLocal>(HiveBoxNames.products);
      final product = ProductLocal(
        id: 'test_prod',
        name: 'منتج اختبار',
        sellingPrice1: 50.0,
        updatedAt: DateTime.now(),
      );
      await box.put('test_prod', product);

      final retrieved = box.get('test_prod');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'منتج اختبار');
      expect(retrieved.sellingPrice1, 50.0);
    });
  });

  // ── ClientLocal model ───────────────────────────────────────────────────

  group('ClientLocal', () {
    test('fromFirestore correctly maps client fields', () {
      final data = {
        'name': 'محمد أحمد',
        'balance': 1500.0,
        'phone': '01012345678',
        'address': 'القاهرة',
      };
      final client = ClientLocal.fromFirestore('client001', data);

      expect(client.id, 'client001');
      expect(client.name, 'محمد أحمد');
      expect(client.balance, 1500.0);
      expect(client.phone, '01012345678');
    });

    test('ClientLocal can be stored and retrieved from Hive box', () async {
      final box = Hive.box<ClientLocal>(HiveBoxNames.clients);
      final client = ClientLocal(
        id: 'test_client',
        name: 'عميل اختبار',
        balance: 2000.0,
        updatedAt: DateTime.now(),
      );
      await box.put('test_client', client);

      final retrieved = box.get('test_client');
      expect(retrieved, isNotNull);
      expect(retrieved!.balance, 2000.0);
    });
  });

  // ── SupplierLocal model ─────────────────────────────────────────────────

  group('SupplierLocal', () {
    test('fromFirestore correctly maps supplier fields', () {
      final data = {
        'name': 'مصنع النصر',
        'balance': 5000.0,
        'phone': '0223456789',
      };
      final supplier = SupplierLocal.fromFirestore('sup001', data);

      expect(supplier.id, 'sup001');
      expect(supplier.name, 'مصنع النصر');
      expect(supplier.balance, 5000.0);
    });
  });

  // ── InvoiceLocal & InvoiceRepository ────────────────────────────────────

  group('InvoiceLocal & InvoiceRepository', () {
    test('Stores and retrieves sales invoices locally', () async {
      final invoice = InvoiceLocal(
        id: 'inv_test_1',
        invoiceNumber: 101,
        clientId: 'c1',
        clientName: 'عميل تجربة',
        date: DateTime(2026, 8, 17),
        totalSum: 500.0,
        paidAmount: 200.0,
        balance: 300.0,
        updatedAt: DateTime.now(),
      );
      await invoicesBox.put('inv_test_1', invoice);

      final fetched = InvoiceRepository.instance.getSaleById('inv_test_1');
      expect(fetched, isNotNull);
      expect(fetched!.invoiceNumber, 101);
      expect(fetched.clientName, 'عميل تجربة');
      expect(fetched.balance, 300.0);

      final byClient = InvoiceRepository.instance.getSalesByClient('c1');
      expect(byClient.length, 1);
      expect(byClient.first.id, 'inv_test_1');
    });
  });

  // ── LocalInvoiceCounter ─────────────────────────────────────────────────

  group('LocalInvoiceCounter', () {
    test('Generates sequential invoice numbers locally with zero latency', () {
      final num1 = LocalInvoiceCounter.nextNumber('sale');
      final num2 = LocalInvoiceCounter.nextNumber('sale');
      final num3 = LocalInvoiceCounter.nextNumber('sale');

      expect(num2, num1 + 1);
      expect(num3, num2 + 1);
    });
  });

  // ── BoxRepository ───────────────────────────────────────────────────────

  group('BoxRepository', () {
    test('Increments and decrements cash box value accurately', () async {
      await BoxRepository.instance.setValue(1000.0);
      expect(BoxRepository.instance.getValue(), 1000.0);

      await BoxRepository.instance.increment(250.0);
      expect(BoxRepository.instance.getValue(), 1250.0);

      await BoxRepository.instance.decrement(100.0);
      expect(BoxRepository.instance.getValue(), 1150.0);
    });
  });

  // ── BalanceHistoryRepository ────────────────────────────────────────────

  group('BalanceHistoryRepository', () {
    test('Stores and retrieves balance history entries ordered by date', () async {
      final entry1 = BalanceHistoryLocal(
        id: 'h1',
        parentId: 'client_hist_1',
        parentType: 'client',
        enteredBalance: 500.0,
        balanceBefore: 0.0,
        type: 'sale',
        timestamp: DateTime(2026, 8, 1, 10, 0),
      );

      final entry2 = BalanceHistoryLocal(
        id: 'h2',
        parentId: 'client_hist_1',
        parentType: 'client',
        enteredBalance: 200.0,
        balanceBefore: 500.0,
        type: 'sale_payment',
        timestamp: DateTime(2026, 8, 1, 10, 30),
      );

      await BalanceHistoryRepository.instance.upsertLocal(entry1);
      await BalanceHistoryRepository.instance.upsertLocal(entry2);

      final history = BalanceHistoryRepository.instance.getForClient('client_hist_1');
      expect(history.length, 2);
      expect(history[0].type, 'sale');
      expect(history[1].type, 'sale_payment');
    });
  });

  // ── SyncQueueManager ────────────────────────────────────────────────────

  group('SyncQueueManager', () {
    setUp(() async {
      await Hive.box<SyncQueueItem>(HiveBoxNames.syncQueue).clear();
    });

    test('enqueue adds an item with status=pending', () async {
      final id = await SyncQueueManager.instance.enqueue(
        operationType: 'createInvoice',
        payload: {'clientId': 'client001', 'invoiceId': 'inv001'},
      );

      expect(id, isNotEmpty);
      expect(SyncQueueManager.instance.pendingCount, 1);

      final pending = SyncQueueManager.instance.getPending();
      expect(pending.first.status, 'pending');
      expect(pending.first.operationType, 'createInvoice');
    });

    test('hasPending returns false when queue is empty', () {
      expect(SyncQueueManager.instance.hasPending, false);
    });

    test('hasPending returns true after enqueueing an item', () async {
      await SyncQueueManager.instance.enqueue(
        operationType: 'editProduct',
        payload: {'productId': 'p1'},
      );
      expect(SyncQueueManager.instance.hasPending, true);
    });

    test('markSynced removes item from queue', () async {
      final id = await SyncQueueManager.instance.enqueue(
        operationType: 'deleteProduct',
        payload: {'productId': 'p2'},
      );
      expect(SyncQueueManager.instance.pendingCount, 1);

      await SyncQueueManager.instance.markSynced(id);
      expect(SyncQueueManager.instance.pendingCount, 0);
    });

    test('markFailed increments retryCount and sets error', () async {
      final id = await SyncQueueManager.instance.enqueue(
        operationType: 'adjustClientBalance',
        payload: {'clientId': 'c1', 'amount': 100.0},
      );

      await SyncQueueManager.instance.markFailed(id, 'Network timeout');

      final item = Hive.box<SyncQueueItem>(HiveBoxNames.syncQueue).get(id);
      expect(item!.status, 'failed');
      expect(item.retryCount, 1);
      expect(item.lastError, 'Network timeout');
    });

    test('resetToPending resets failed item back to pending', () async {
      final id = await SyncQueueManager.instance.enqueue(
        operationType: 'createProduct',
        payload: {'productId': 'p3'},
      );
      await SyncQueueManager.instance.markFailed(id, 'Error');
      await SyncQueueManager.instance.resetToPending(id);

      final item = Hive.box<SyncQueueItem>(HiveBoxNames.syncQueue).get(id);
      expect(item!.status, 'pending');
    });

    test('getPending orders items by createdAt ascending', () async {
      await SyncQueueManager.instance.enqueue(
        operationType: 'createInvoice',
        payload: {'invoiceId': 'first'},
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await SyncQueueManager.instance.enqueue(
        operationType: 'editInvoice',
        payload: {'invoiceId': 'second'},
      );

      final pending = SyncQueueManager.instance.getPending();
      expect(pending.length, 2);
      expect(pending[0].createdAt.isBefore(pending[1].createdAt), true);
    });

    test('decodePayload correctly restores Map from JSON', () async {
      final payload = {
        'clientId': 'client123',
        'amount': 250.5,
        'isAddition': true,
      };
      final id = await SyncQueueManager.instance.enqueue(
        operationType: 'adjustClientBalance',
        payload: payload,
      );

      final item = Hive.box<SyncQueueItem>(HiveBoxNames.syncQueue).get(id)!;
      final decoded = SyncQueueManager.decodePayload(item);

      expect(decoded['clientId'], 'client123');
      expect(decoded['amount'], 250.5);
      expect(decoded['isAddition'], true);
    });
  });
}
