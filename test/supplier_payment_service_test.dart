import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/supplier_payment_service.dart';
import 'package:kareem_store/Services/supplier_ledger_presentation.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/local_db/models/box_local.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/supplier_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/repositories/box_repository.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('supplier_payment_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(SupplierLocalAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SyncQueueItemAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(InvoiceLocalAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(BoxLocalAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(BalanceHistoryLocalAdapter());
    }

    await Hive.openBox<SupplierLocal>(HiveBoxNames.suppliers);
    await Hive.openBox<SyncQueueItem>(HiveBoxNames.syncQueue);
    await Hive.openBox(HiveBoxNames.appMeta);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingInvoices);
    await Hive.openBox<InvoiceLocal>(HiveBoxNames.buyingReturnInvoices);
    await Hive.openBox<BoxLocal>(HiveBoxNames.box);
    await Hive.openBox<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
  });

  setUp(() async {
    await Future.wait([
      suppliersBox.clear(),
      syncQueueBox.clear(),
      appMetaBox.clear(),
      buyingInvoicesBox.clear(),
      buyingReturnInvoicesBox.clear(),
      boxCacheBox.clear(),
      balanceHistoryBox.clear(),
    ]);
    await suppliersBox.put(
      'supplier-1',
      SupplierLocal(
        id: 'supplier-1',
        name: 'Local Supplier',
        balance: 500,
        updatedAt: DateTime.now(),
      ),
    );
    await BalanceHistoryRepository.instance.upsertLocal(
      BalanceHistoryLocal(
        id: 'supplier-opening',
        parentId: 'supplier-1',
        parentType: 'supplier',
        enteredBalance: 500,
        type: 'opening',
        direction: 'له',
        timestamp: DateTime(2026, 9, 1),
      ),
    );
    await BoxRepository.instance.setValue(1000);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('عليه reduces supplier balance and local cash before queueing',
      () async {
    await SupplierPaymentService.instance.save(
      supplierId: 'supplier-1',
      supplierName: 'Local Supplier',
      direction: 'عليه',
      amount: 125,
      description: 'Cash payment',
      date: DateTime(2026, 9, 10),
      paymentMethod: 'نقداً',
      voucherNumber: 17,
    );

    expect(
      BalanceHistoryRepository.instance.calculateSupplierBalance('supplier-1'),
      375,
    );
    expect(BoxRepository.instance.getValue(), 875);
    expect(SyncQueueManager.instance.pendingCount, 1);

    final payload = SyncQueueManager.decodePayload(
      SyncQueueManager.instance.getPending().single,
    );
    expect(payload['direction'], 'عليه');
    expect(payload['voucherNumber'], 17);
    expect(payload['paymentMethod'], 'نقداً');
    expect(payload['historyId'], isNotEmpty);
    expect(payload['voucherId'], isNotEmpty);
  });

  test('له increases supplier balance without changing local cash', () async {
    await SupplierPaymentService.instance.save(
      supplierId: 'supplier-1',
      supplierName: 'Local Supplier',
      direction: 'له',
      amount: 80,
      description: 'Credit adjustment',
      date: DateTime(2026, 9, 10),
      paymentMethod: 'شيك',
      voucherNumber: 18,
    );

    expect(
      BalanceHistoryRepository.instance.calculateSupplierBalance('supplier-1'),
      580,
    );
    expect(BoxRepository.instance.getValue(), 1000);
    expect(SyncQueueManager.instance.pendingCount, 1);
    final history = BalanceHistoryRepository.instance
        .getForSupplier('supplier-1')
        .where((entry) => entry.type == 'voucher')
        .single;
    expect(history.direction, 'له');
    expect(
      SupplierLedgerPresentation.voucherLabel(history.direction),
      'إضافة رصيد للمورد',
    );
    expect(SupplierLedgerPresentation.voucherSign(history.direction), '+');
  });

  test('عليه voucher is presented as a negative supplier payment', () {
    expect(
      SupplierLedgerPresentation.voucherLabel('عليه'),
      'سداد نقدي للمورد',
    );
    expect(SupplierLedgerPresentation.voucherSign('عليه'), '-');
    expect(SupplierLedgerPresentation.voucherSign(null), '-');
  });

  test('purchase returns and their refunds use the supplier ledger', () async {
    await buyingReturnInvoicesBox.put(
      'return-1',
      InvoiceLocal(
        id: 'return-1',
        invoiceNumber: 31,
        supplierId: 'supplier-1',
        supplierName: 'Local Supplier',
        date: DateTime(2026, 9, 5),
        totalSum: 300,
        paidAmount: 100,
        balance: 200,
        previousBalance: 500,
        invoiceType: 'buying_return',
        updatedAt: DateTime(2026, 9, 5),
      ),
    );

    final history =
        BalanceHistoryRepository.instance.getForSupplier('supplier-1');

    expect(
        history.where((entry) => entry.type == 'buying_return'), hasLength(1));
    expect(
      history.where((entry) => entry.type == 'buying_return_payment'),
      hasLength(1),
    );
    expect(
      BalanceHistoryRepository.instance.calculateSupplierBalance('supplier-1'),
      300,
    );
  });
}
