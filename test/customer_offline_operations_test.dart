import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/client_local.dart';
import 'package:kareem_store/local_db/models/product_local.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/box_local.dart';
import 'package:kareem_store/local_db/models/quote_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/Services/customer_balance_store.dart';
import 'package:kareem_store/Services/customer_operation_service.dart';
import 'package:kareem_store/Services/invoice_footer_data.dart';
import 'package:kareem_store/Services/invoice_print_service.dart';
import 'package:kareem_store/Services/customer_balance_review.dart';
import 'package:kareem_store/Services/customer_local_views.dart';
import 'package:kareem_store/Services/customer_statement_data.dart';
import 'package:kareem_store/repositories/quote_repository.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/Widgets/invoice_display_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kareem_store/Services/sales_invoice_actions_service.dart';
import 'package:kareem_store/repositories/client_repository.dart';
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/repositories/product_repository.dart';
import 'package:kareem_store/repositories/box_repository.dart';
import 'package:kareem_store/sync/local_operation_journal.dart';
import 'package:kareem_store/sync/cloud_snapshot_guard.dart';
import 'package:kareem_store/sync/financial_cloud_store.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';
import 'package:kareem_store/sync/batch_sync_engine.dart';

/// Atomic fake backend: exercises the production transaction planner. No Firebase
/// initialization, credentials, network, or production data is used by these tests.
class MemoryCloud extends FinancialCloudStore {
  Map<String, Map<String, dynamic>> documents = {};
  bool failBeforeCommit = false, loseAcknowledgement = false;
  final Set<String> failOperationIds = {};
  int attempts = 0;
  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
          String clientId) async =>
      {
        for (final entry in documents.entries)
          if (entry.key
              .startsWith('clients/' + clientId + '/financialOperations/'))
            entry.key.split('/').last: entry.value,
      };
  @override
  Future<Map<String, dynamic>> transaction(
      Future<Map<String, dynamic>> Function(FinancialTransaction)
          action) async {
    attempts++;
    final tx = MemoryTransaction(documents, failOperationIds);
    final result = await action(tx);
    if (failBeforeCommit) throw StateError('test network failure');
    documents = {...documents, ...tx.writes};
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw StateError('test acknowledgement lost after commit');
    }
    return result;
  }
}

class MemoryTransaction implements FinancialTransaction {
  final Map<String, Map<String, dynamic>> before;
  final Map<String, Map<String, dynamic>> writes = {};
  final Set<String> failOperationIds;
  MemoryTransaction(this.before, this.failOperationIds);
  @override
  Future<Map<String, dynamic>?> read(String path) async {
    if (writes.isNotEmpty) throw StateError('read after write');
    if (path.startsWith('financial_operation_receipts/')) {
      final operationId = path.split('/').last;
      if (failOperationIds.remove(operationId)) {
        throw StateError('test network failure for $operationId');
      }
    }
    final data = before[path];
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  @override
  void write(String path, Map<String, dynamic> data) => writes[path] = data;
}

void main() {
  late Directory directory;
  late MemoryCloud cloud;
  final date = DateTime(2026, 1, 10);
  Future<void> openBoxes() async {
    await Hive.openBox<ClientLocal>(HiveBoxNames.clients);
    await Hive.openBox<ProductLocal>(HiveBoxNames.products);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.invoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.returnInvoices);
    await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
    await Hive.openBox<BoxLocal>(HiveBoxNames.box);
    await Hive.openBox<QuoteLocal>(HiveBoxNames.quotes);
    await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
    await Hive.openBox(HiveBoxNames.appMeta);
  }

  Map<String, dynamic> invoice(
          {String id = 's',
          double total = 100,
          double paid = 20,
          double quantity = 2,
          String client = 'c',
          String product = 'p'}) =>
      {
        'id': id,
        'invoiceNumber': 1,
        'clientId': client,
        'clientName': client == 'c' ? 'Test customer' : 'Second customer',
        'totalSum': total,
        'paidAmount': paid,
        'date': date,
        'products': [
          {
            'id': product,
            'product': product == 'p' ? 'Test product' : 'Second product',
            'amount': quantity,
            'selectedPrice': 50,
            'total': total
          }
        ],
      };
  void expectLocal(double balance, double stock, double cash) {
    expect(CustomerBalanceStore.balance('c'), balance);
    expect(clientsBox.get('c')!.balance, balance);
    expect(productsBox.get('p')!.quantity, stock);
    expect(boxCacheBox.get('mainBox')!.value, cash);
  }

  void expectCloud(double balance, double stock, double cash) {
    expect(cloud.documents['clients/c']!['balance'], balance);
    expect(cloud.documents['products/p']!['quantity'], stock);
    expect(cloud.documents['box/mainBox']!['value'], cash);
  }

  Future<void> drain() => BatchSyncEngine.forTesting(cloud).processQueue();
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('financial_test_');
    Hive.init(directory.path);
    Hive.registerAdapter(ClientLocalAdapter());
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
      productsBox,
      invoicesBox,
      returnInvoicesBox,
      balanceHistoryBox,
      boxCacheBox,
      quotesBox,
      syncQueueBox,
      appMetaBox
    ]) {
      await box.clear();
    }
    await clientsBox.put(
        'c',
        ClientLocal(
            id: 'c', name: 'Test customer', balance: 50, updatedAt: date));
    await productsBox.put(
        'p',
        ProductLocal.fromFirestore('p', {
          'name': 'Test product',
          'quantity': 10.0,
          'costPrice': 20.0,
          'sellingPrice1': 50.0
        }));
    await boxCacheBox.put(
        'mainBox', BoxLocal(id: 'mainBox', value: 100, updatedAt: date));
    await CustomerBalanceStore.preserveExistingBalances();
    cloud = MemoryCloud()
      ..documents = {
        'clients/c': CustomerOperationService.clientMap('c'),
        'products/p': productsBox.get('p')!.toMap(),
        'box/mainBox': boxCacheBox.get('mainBox')!.toMap(),
      };
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('legacy financial uploads remain visible and cannot be replayed blindly',
      () async {
    await SyncQueueManager.instance.enqueue(
        operationType: 'adjustClientBalance',
        payload: {'clientId': 'c', 'amount': 25, 'isAddition': false});
    await drain();
    expectCloud(50, 10, 100);
    expectLocal(50, 10, 100);
    expect(cloud.attempts, 0);
    expect(syncQueueBox.values.single.lastError, contains('requires review'));
  });
  test('statement exports use accepted local balances and shared footer values',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: false,
        notes: '',
        date: date.add(const Duration(days: 1)));
    final rows = CustomerStatementData.financialHistory('c');
    expect(rows.first['balanceBefore'], 50);
    expect(rows.last['balanceAfter'], CustomerBalanceStore.balance('c'));
    final exported = CustomerStatementData.invoices('c').single;
    final sales = InvoiceFooterData.fromInvoice(invoicesBox.get('s')!.toMap());
    expect(InvoiceFooterData.fromInvoice(exported).rows, sales.rows);
    expectLocal(120, 8, 130);
  });
  test('exhausted predecessor cannot be overtaken by a later invoice edit',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    final first = syncQueueBox.values.single;
    first.status = 'failed';
    first.retryCount = 5;
    await first.save();
    await CustomerOperationService.saveInvoice(
        invoice(total: 150, paid: 30, quantity: 3),
        editing: true);
    await drain();
    expect(cloud.attempts, 0);
    expect(syncQueueBox.length, 2);
    expectLocal(170, 7, 130);
  });
  test('failed invoice only blocks later operations sharing its resources',
      () async {
    await clientsBox.put(
        'c2',
        ClientLocal(
            id: 'c2', name: 'Second customer', balance: 10, updatedAt: date));
    await productsBox.put(
        'p2',
        ProductLocal.fromFirestore('p2', {
          'name': 'Second product',
          'quantity': 20.0,
          'costPrice': 10.0,
          'sellingPrice1': 50.0
        }));
    await CustomerBalanceStore.preserveExistingBalances();
    cloud.documents['clients/c2'] = CustomerOperationService.clientMap('c2');
    cloud.documents['products/p2'] = productsBox.get('p2')!.toMap();

    await CustomerOperationService.saveInvoice(
        invoice(id: 'blocked', total: 50, paid: 0, quantity: 1));
    final blockedOperation = syncQueueBox.values.single.operationId;
    await CustomerOperationService.saveInvoice(invoice(
        id: 'independent',
        total: 100,
        paid: 0,
        quantity: 2,
        client: 'c2',
        product: 'p2'));
    cloud.failOperationIds.add(blockedOperation);

    await drain();

    expect(syncQueueBox.length, 1);
    expect(syncQueueBox.get(blockedOperation)!.status, 'failed');
    expect(cloud.documents['invoices/blocked'], isNull);
    expect(cloud.documents['invoices/independent'], isNotNull);
    expect(cloud.documents['clients/c2']!['balance'], 110);
    expect(cloud.documents['products/p2']!['quantity'], 18);
  });
  test(
      'post-upload refresh catches remote effects whose snapshots arrived while protected',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    cloud.documents['products/p']!['quantity'] = 12.0;
    cloud.documents['box/mainBox']!['value'] = 110.0;
    cloud.documents['clients/c']!['balance'] = 57.0;
    cloud.documents['clients/c/financialOperations/remote'] = {
      'delta': 7.0,
      'operationId': 'remote'
    };
    await drain();
    expectLocal(137, 10, 130);
    expectCloud(137, 10, 130);
    await drain();
    expectLocal(137, 10, 130);
  });
  test('acknowledging an older receipt never reduces an imported cloud version',
      () async {
    await appMetaBox.put(CloudSnapshotGuard.versionKey('invoices/s'), 5);
    await CloudSnapshotGuard.acknowledge({
      'versions': {'invoices/s': 2}
    });
    expect(CloudSnapshotGuard.accepts('invoices/s', {'_version': 3}), false);
  });
  test(
      'new device imports baseline and existing receipts once before showing customer',
      () async {
    await ClientRepository.instance.mergeCloud('new', {
      'clientName': 'Remote test',
      'balance': 130.0,
      'financialBaseBalance': 50.0,
    }, events: {
      'existing': {'delta': 80.0}
    });
    expect(clientsBox.get('new')!.balance, 130);
    await CustomerBalanceStore.importEvent('new', 'existing', {'delta': 80.0});
    expect(CustomerBalanceStore.balance('new'), 130);
  });
  test('Firestore timestamps in customer events are converted before Hive save',
      () async {
    final timestamp = Timestamp.fromDate(DateTime(2026, 9, 28, 23, 22));
    await CustomerBalanceStore.importEvent('c', 'timestamp-event', {
      'delta': 5.0,
      'appliedAt': timestamp,
      'nested': [
        {'timestamp': timestamp}
      ],
    });

    final saved = appMetaBox
        .get(CustomerBalanceStore.eventKey('c', 'timestamp-event')) as Map;
    expect(saved['appliedAt'], isA<DateTime>());
    expect((saved['nested'] as List).single['timestamp'], isA<DateTime>());
    expect(CustomerBalanceStore.balance('c'), 55);
  });
  test('quote execution is durable and cannot make a second sale', () async {
    await quotesBox.put('q', QuoteLocal.fromFirestore('q', invoice()));
    await CustomerOperationService.saveInvoice(invoice(), quoteId: 'q');
    expect(quotesBox.isEmpty, true);
    expectLocal(130, 8, 120);
    await QuoteRepository.instance.mergeCloud('q', invoice());
    expect(quotesBox.isEmpty, true);
    await expectLater(
        CustomerOperationService.saveInvoice(invoice(), quoteId: 'q'),
        throwsStateError);
    await drain();
    expectCloud(130, 8, 120);
    expect(cloud.documents['price_quotes/q']!['_deleted'], true);
  });
  test(
      'quote creation, editing and deletion are durable and have no financial effect',
      () async {
    await CustomerOperationService.saveQuote(invoice(id: 'q'));
    await Hive.close();
    await openBoxes();
    await LocalOperationJournal.recover();
    expect(quotesBox.get('q')!.date, date);
    expectLocal(50, 10, 100);
    await CustomerOperationService.saveQuote(invoice(id: 'q', total: 150),
        editing: true);
    await CustomerOperationService.deleteQuote('q');
    await drain();
    expectLocal(50, 10, 100);
    expectCloud(50, 10, 100);
    expect(quotesBox.isEmpty, true);
    expect(syncQueueBox.isEmpty, true);
    expect(cloud.documents['price_quotes/q']!['_deleted'], true);
  });
  test(
      'cash adjustment uploads once instead of direct write plus queue increment',
      () async {
    await CustomerOperationService.changeCash(15);
    final item = syncQueueBox.values.single;
    await FinancialCloudUploader.upload(
        item.operationId, SyncQueueManager.decodePayload(item), cloud);
    await drain();
    expectCloud(50, 10, 115);
    expectLocal(50, 10, 115);
  });
  test(
      'balance review only shows differences and does not repair historical data',
      () async {
    final beforeQueue = syncQueueBox.length;
    final rows = CustomerBalanceReview.rows();
    expect(rows.single['accepted'], 50);
    expect(rows.single['cachedHistory'], 0);
    expect(rows.single['difference'], 50);
    expect(syncQueueBox.length, beforeQueue);
    expectLocal(50, 10, 100);
  });
  test(
      'journal order survives a clock earlier than an existing queued operation',
      () async {
    final future = DateTime.now().add(const Duration(days: 1));
    await syncQueueBox.put(
        'earlier',
        SyncQueueItem(
            operationId: 'earlier',
            operationType: 'test',
            payloadJson:
                '{"financialFormat":2,"cloudWrites":[],"customerDeltas":{}}',
            createdAt: future));
    await CustomerOperationService.saveInvoice(invoice());
    final items = SyncQueueManager.instance.getPending();
    expect(items.first.operationId, 'earlier');
    expect(items.last.createdAt.isAfter(future), true);
  });
  test('restart restores a mirror after a remote ledger event was flushed',
      () async {
    await appMetaBox
        .put(CustomerBalanceStore.eventKey('c', 'remote'), {'delta': 5.0});
    await appMetaBox.flush();
    await Hive.close();
    await openBoxes();
    await CustomerBalanceStore.preserveExistingBalances();
    expectLocal(55, 10, 100);
    expect(syncQueueBox.isEmpty, true);
  });
  test('opening balances precede backdated invoices in both footer payloads',
      () async {
    final id = await CustomerOperationService.createClient(
        name: 'Backdated test', openingBalance: 70);
    await CustomerOperationService.saveInvoice(
        {...invoice(), 'clientId': id, 'clientName': 'Backdated test'});
    final footer = InvoiceFooterData.fromInvoice(invoicesBox.get('s')!.toMap());
    expect(footer.previous, 70);
    expect(footer.remaining, 150);
  });
  test(
      'return footer uses the same refund and balance values as the customer ledger',
      () async {
    await CustomerOperationService.saveInvoice(
        invoice(id: 'r', total: 40, paid: 10, quantity: 1),
        isReturn: true);
    final data = returnInvoicesBox.get('r')!.toMap();
    final customer = InvoiceFooterData.fromInvoice(
        SalesInvoiceActionsService.buildClientPagePayload(data));
    final sales = InvoiceFooterData.fromInvoice(data);
    expect(sales.rows, customer.rows);
    expect(sales.previous, 50);
    expect(sales.remaining, 20);
  });
  test('customer lists and reports use the ledger without network access',
      () async {
    await CustomerOperationService.savePayment(
        clientId: 'c', amount: 75, isAddition: false, notes: 'test');
    expect(CustomerLocalViews.snapshot(balanceSign: -1).docs.single['balance'],
        -25);
    expect(CustomerLocalViews.snapshot(balanceSign: 1).docs, isEmpty);
    expect(CustomerLocalViews.snapshot().docs.single['balance'], -25);
  });
  test(
      'both Arabic voucher directions retain their existing debt and cash rules',
      () async {
    expect(CustomerOperationService.voucherAddsDebt('عليه'), true);
    expect(CustomerOperationService.voucherAddsDebt('له'), false);
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: CustomerOperationService.voucherAddsDebt('عليه'),
        notes: '');
    expectLocal(60, 10, 90);
    await drain();
    expectCloud(60, 10, 90);
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: CustomerOperationService.voucherAddsDebt('له'),
        notes: '');
    expectLocal(50, 10, 100);
    await drain();
    expectCloud(50, 10, 100);
  });
  test(
      'stale payment history cannot overwrite pending edits or resurrect deleted entries',
      () async {
    await CustomerOperationService.savePayment(
        clientId: 'c', amount: 20, isAddition: false, notes: '');
    final entry = balanceHistoryBox.values.single;
    final stale = entry.toMap();
    await drain();
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: false,
        notes: '',
        historyId: entry.id);
    await BalanceHistoryRepository.instance
        .mergeCloudClientHistory('c', entry.id, stale);
    expect(balanceHistoryBox.values.single.enteredBalance, 10);
    await drain();
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: false,
        notes: '',
        historyId: entry.id,
        deleting: true);
    await drain();
    await BalanceHistoryRepository.instance
        .mergeCloudClientHistory('c', entry.id, stale);
    expect(balanceHistoryBox.isEmpty, true);
    expectLocal(50, 10, 100);
  });
  test(
      'deleting invoice payment through an invoice edit reverses cash and debt only',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await CustomerOperationService.saveInvoice(invoice(paid: 0), editing: true);
    expectLocal(150, 8, 100);
    await drain();
    expectCloud(150, 8, 100);
    expect(
        BalanceHistoryRepository.instance
            .getForClient('c')
            .where((e) => e.type == 'sale_payment'),
        isEmpty);
  });
  testWidgets(
      'both page payloads render identical footer text and Arabic labels',
      (tester) async {
    await tester.runAsync(() => CustomerOperationService.saveInvoice(
        {...invoice(), 'invoiceDiscount': 10}));
    Future<List<String>> render(Map<String, dynamic> data) async {
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(1200, 900),
          builder: (_, __) => MaterialApp(
              home: Scaffold(body: InvoiceTotalsFooter(invoice: data)))));
      await tester.pump();
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .toList();
    }

    final customer = await render(
        SalesInvoiceActionsService.buildClientPagePayload(
            invoicesBox.get('s')!.toMap()));
    final sales =
        await render({...invoice(), 'balance': 999, 'invoiceDiscount': 0});
    expect(sales, customer);
    expect(sales, contains('خصم الفاتورة: 10'));
    expect(sales.any((text) => text.startsWith('المتبقي عليكم:')), true);
    expect(tester.takeException(), isNull);
  });

  test(
      'offline sale commits balance, frozen cost, stock, cash and outbox together',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    expectLocal(130, 8, 120);
    expectCloud(50, 10, 100);
    expect(syncQueueBox.values.single.status, 'pending');
    expect(invoicesBox.get('s')!.products.single['costPrice'], 20);
    expect(invoicesBox.get('s')!.profitMargin, 60);
  });
  test('cash overpayment is stored once as cash and customer credit', () async {
    await CustomerOperationService.saveInvoice(invoice(paid: 120));

    expectLocal(30, 8, 220);
    expect(invoicesBox.get('s')!.paidAmount, 120);
    expect(invoicesBox.get('s')!.balance, 30);
    expect(syncQueueBox.length, 1);

    await drain();
    expectCloud(30, 8, 220);
  });
  test('repeated transaction attempts apply every financial effect once',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    final item = syncQueueBox.values.single;
    final payload = SyncQueueManager.decodePayload(item);
    for (var i = 0; i < 3; i++) {
      await FinancialCloudUploader.upload(item.operationId, payload, cloud);
    }
    expectLocal(130, 8, 120);
    expectCloud(130, 8, 120);
    expect(
        cloud.documents.keys.where((p) =>
            p.startsWith('financial_operation_receipts/') &&
            p != FinancialCloudUploader.feedHeadPath),
        hasLength(1));
    final receipt =
        cloud.documents['financial_operation_receipts/${item.operationId}']!;
    expect(receipt['sequence'], 1);
    expect(receipt['customerIds'], ['c']);
    expect((receipt['versions'] as Map).keys, contains('invoices/s'));
    expect(
        cloud.documents[FinancialCloudUploader.feedHeadPath]!['lastSequence'],
        1);
    expect(
        cloud.documents.keys.where((p) => p.startsWith('box/mainBox/changes/')),
        hasLength(1));
  });
  test('restart before upload retains outbox and unchanged financial effects',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await Hive.close();
    await openBoxes();
    await LocalOperationJournal.recover();
    expectLocal(130, 8, 120);
    expect(syncQueueBox.length, 1);
    await drain();
    await drain();
    expectCloud(130, 8, 120);
    expectLocal(130, 8, 120);
    expect(syncQueueBox.isEmpty, true);
  });
  test(
      'interrupted preparing record recovers a partially applied save after restart',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    final item = syncQueueBox.values.single;
    // Simulate interruption after journaling and stock write but before customer/cash writes.
    item.status = 'preparing';
    await item.save();
    await syncQueueBox.flush();
    await invoicesBox.clear();
    await balanceHistoryBox.clear();
    await appMetaBox.clear();
    await appMetaBox.put(CustomerBalanceStore.baseKey('c'), 50.0);
    clientsBox.get('c')!.balance = 50;
    await clientsBox.get('c')!.save();
    boxCacheBox.get('mainBox')!.value = 100;
    await boxCacheBox.get('mainBox')!.save();
    await Hive.close();
    await openBoxes();
    await LocalOperationJournal.recover();
    await LocalOperationJournal.recover();
    expectLocal(130, 8, 120);
    expect(invoicesBox.length, 1);
    expect(syncQueueBox.values.single.status, 'pending');
    await drain();
    expectCloud(130, 8, 120);
  });
  test('failure then reconnect retains operation and uploads once', () async {
    await CustomerOperationService.saveInvoice(invoice());
    cloud.failBeforeCommit = true;
    await drain();
    expect(syncQueueBox.values.single.status, 'failed');
    expect(
        syncQueueBox.values.single.lastError, contains('test network failure'));
    expectCloud(50, 10, 100);
    expectLocal(130, 8, 120);
    cloud.failBeforeCommit = false;
    await SyncQueueManager.instance.resetFailedItems();
    await drain();
    await drain();
    expectCloud(130, 8, 120);
    expectLocal(130, 8, 120);
  });
  test(
      'lost acknowledgement and restart cannot double apply stock, balance or cash',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    cloud.loseAcknowledgement = true;
    await drain();
    expectCloud(130, 8, 120);
    await Hive.close();
    await openBoxes();
    await SyncQueueManager.instance.resetFailedItems();
    await drain();
    expectCloud(130, 8, 120);
    expectLocal(130, 8, 120);
    expect(syncQueueBox.isEmpty, true);
  });
  test('offline create, edit and deletion synchronize in dependency order',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await CustomerOperationService.saveInvoice(
        invoice(total: 150, paid: 30, quantity: 3),
        editing: true);
    expectLocal(170, 7, 130);
    await CustomerOperationService.deleteInvoice('s');
    expectLocal(50, 10, 100);
    expect(invoicesBox.isEmpty, true);
    expect(syncQueueBox.length, 3);
    await drain();
    expectCloud(50, 10, 100);
    expect(syncQueueBox.isEmpty, true);
    expect(cloud.documents['invoices/s']!['_deleted'], true);
  });
  test('return and refund, edit and deletion reverse debt, stock and cash',
      () async {
    await CustomerOperationService.saveInvoice(
        invoice(id: 'r', total: 40, paid: 10, quantity: 1),
        isReturn: true);
    expectLocal(20, 11, 90);
    await CustomerOperationService.saveInvoice(
        invoice(id: 'r', total: 60, paid: 15, quantity: 2),
        isReturn: true,
        editing: true);
    expectLocal(5, 12, 85);
    await drain();
    expectCloud(5, 12, 85);
    await CustomerOperationService.deleteInvoice('r', isReturn: true);
    expectLocal(50, 10, 100);
    await drain();
    expectCloud(50, 10, 100);
  });
  test('payment/voucher edit and deletion preserve one debt and cash effect',
      () async {
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 20,
        isAddition: false,
        notes: 'test',
        voucher: {'amount': 20, 'clientId': 'c'});
    expectLocal(30, 10, 120);
    final history = balanceHistoryBox.values.single.id;
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: false,
        notes: 'edited',
        historyId: history);
    expectLocal(40, 10, 110);
    await drain();
    expectCloud(40, 10, 110);
    expect(cloud.documents['client_vouchers/$history']!['amount'], 10);
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 10,
        isAddition: false,
        notes: '',
        historyId: history,
        deleting: true);
    expectLocal(50, 10, 100);
    await drain();
    expectCloud(50, 10, 100);
    expect(cloud.documents['client_vouchers/$history']!['_deleted'], true);
  });
  test('opening balance creation and edits do not touch cash or stock',
      () async {
    final id = await CustomerOperationService.createClient(
        name: 'New test', openingBalance: 70);
    expect(CustomerBalanceStore.balance(id), 70);
    final history = balanceHistoryBox.values.single.id;
    await CustomerOperationService.savePayment(
        clientId: id,
        amount: 90,
        isAddition: true,
        notes: '',
        historyId: history);
    await drain();
    expect(CustomerBalanceStore.balance(id), 90);
    expect(cloud.documents['clients/$id']!['balance'], 90);
    expectLocal(50, 10, 100);
  });
  test(
      'stale snapshots during pending upload and after acknowledgement cannot overwrite Hive',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    final stale = Map<String, dynamic>.from(invoice())..['totalSum'] = 5;
    Future<void> staleRefresh() async {
      await ClientRepository.instance
          .mergeCloud('c', {'clientName': 'Test customer', 'balance': 999.0});
      await InvoiceRepository.instance
          .mergeCloudInvoice('invoices', 's', stale);
      await ProductRepository.instance
          .mergeCloud('p', {'name': 'Test product', 'quantity': 99.0});
      await BoxRepository.instance.mergeCloud({'value': 999.0});
    }

    await staleRefresh();
    expectLocal(130, 8, 120);
    expect(invoicesBox.get('s')!.totalSum, 100);
    await drain();
    await staleRefresh();
    expectLocal(130, 8, 120);
    expect(invoicesBox.get('s')!.totalSum, 100);
    expect(CloudSnapshotGuard.accepts('invoices/s', null), false);
  });
  test(
      'duplicate remote receipt and echoed balance do not change a local operation twice',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await drain();
    final path = cloud.documents.keys
        .singleWhere((p) => p.startsWith('clients/c/financialOperations/'));
    final id = path.split('/').last;
    await CustomerBalanceStore.importEvent('c', id, cloud.documents[path]!);
    await CustomerBalanceStore.importEvent('c', id, cloud.documents[path]!);
    await ClientRepository.instance
        .mergeCloud('c', cloud.documents['clients/c']);
    expectLocal(130, 8, 120);
  });
  test(
      'concurrent invoice line edit stops upload before any balance, cash or stock mutation',
      () async {
    await CustomerOperationService.saveInvoice(invoice());
    await drain();
    cloud.documents['invoices/s'] = {
      ...cloud.documents['invoices/s']!,
      'products': [
        {
          'product': 'Test product',
          'amount': 9,
          'selectedPrice': 50,
          'total': 100
        }
      ]
    };
    await CustomerOperationService.saveInvoice(
        invoice(total: 150, paid: 30, quantity: 3),
        editing: true);
    await drain();
    expectCloud(130, 8, 120);
    expect(syncQueueBox.values.single.status, 'failed');
    expect(syncQueueBox.values.single.lastError,
        contains('lines or customer changed'));
  });
  test(
      'changing customer transfers invoice debt without changing cash or stock',
      () async {
    await clientsBox.put(
        'c2',
        ClientLocal(
            id: 'c2', name: 'Second customer', balance: 0, updatedAt: date));
    await CustomerBalanceStore.preserveExistingBalances();
    cloud.documents['clients/c2'] = CustomerOperationService.clientMap('c2');
    await CustomerOperationService.saveInvoice(invoice());
    await drain();
    await CustomerOperationService.saveInvoice(invoice(client: 'c2'),
        editing: true);
    expectLocal(50, 8, 120);
    expect(CustomerBalanceStore.balance('c2'), 80);
    await drain();
    expectCloud(50, 8, 120);
    expect(cloud.documents['clients/c2']!['balance'], 80);
  });
  test(
      'same invoice produces identical customer-page and sales-page footer rows',
      () async {
    await CustomerOperationService.saveInvoice(
        {...invoice(), 'invoiceDiscount': 10});
    await CustomerOperationService.savePayment(
        clientId: 'c',
        amount: 5,
        isAddition: false,
        notes: '',
        date: date.add(const Duration(days: 1)));
    final customerPayload = SalesInvoiceActionsService.buildClientPagePayload(
        invoicesBox.get('s')!.toMap());
    final salesPayload = {
      ...invoice(),
      'balance': 999.0,
      'previousBalance': -50.0,
      'invoiceDiscount': 0
    };
    final customerFooter = InvoiceFooterData.fromInvoice(customerPayload);
    final salesFooter = InvoiceFooterData.fromInvoice(salesPayload);
    expect(salesFooter.rows, customerFooter.rows);
    expect(salesFooter.previous, 50);
    expect(salesFooter.remaining, 130);
    expect(salesFooter.discount, 10);
    expect(salesFooter.rows.join(' '), contains('خصم الفاتورة'));
  });
  test(
      'printing uses an unsynced Hive invoice edit instead of stale screen data',
      () async {
    final stale = invoice();
    await CustomerOperationService.saveInvoice(stale);
    await CustomerOperationService.saveInvoice(
      invoice(total: 150, paid: 30, quantity: 3),
      editing: true,
    );

    final printable = await InvoicePrintService.prepareForPrint(
      stale,
      clientId: 'c',
    );

    expect(printable['totalSum'], 150);
    expect(printable['paidAmount'], 30);
    expect(
        double.parse(
            (printable['products'] as List).single['amount'].toString()),
        3);
    expect(cloud.documents.containsKey('invoices/s'), isFalse);
  });
  test('missing local product rejects save before any financial or queue write',
      () async {
    await productsBox.clear();
    await expectLater(
        CustomerOperationService.saveInvoice(invoice()), throwsStateError);
    expect(CustomerBalanceStore.balance('c'), 50);
    expect(invoicesBox.isEmpty, true);
    expect(syncQueueBox.isEmpty, true);
    expect(boxCacheBox.get('mainBox')!.value, 100);
  });
}
