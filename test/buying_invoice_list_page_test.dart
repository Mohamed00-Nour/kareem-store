import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kareem_store/Buing Invoices/BuyingInvoiceListPage.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/supplier_local.dart';
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/sync/local_operation_journal.dart';

void main() {
  late Directory directory;

  Map<String, dynamic> invoice(int number,
          {String supplierName = 'Match supplier', DateTime? date}) =>
      {
        'supplierId': 'supplier',
        'supplierName': supplierName,
        'invoiceNumber': number,
        'date': date ?? DateTime.now(),
        'totalSum': 100.0,
        'paidAmount': 0.0,
        'products': [],
        '_version': 1,
      };

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(800, 600),
      builder: (_, __) => const MaterialApp(home: BuyingInvoiceListPage()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});
    directory = await Directory.systemTemp.createTemp('buying_invoice_list_');
    await initHive(directory: directory.path);
    await suppliersBox.put(
        'supplier',
        SupplierLocal(
          id: 'supplier',
          name: 'Match supplier',
          balance: 100,
          updatedAt: DateTime.now(),
        ));
    await appMetaBox.put('supplierBalanceBase:supplier', 100.0);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('open purchase list updates after local and synced changes',
      (tester) async {
    await openPage(tester);
    await tester.runAsync(() =>
        InvoiceRepository.instance.upsertBuyingLocal('local', invoice(1)));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #1'), findsOneWidget);
    await tester.runAsync(() =>
        InvoiceRepository.instance.mergeCloudBuying('remote', invoice(2)));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #2'), findsOneWidget);
    await tester.runAsync(() => InvoiceRepository.instance
        .mergeCloudBuying('remote', {...invoice(3), '_version': 2}));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #2'), findsNothing);
    expect(find.text('فاتورة #3'), findsOneWidget);
    await tester.runAsync(() => InvoiceRepository.instance.mergeCloudBuying(
        'remote', {...invoice(3), '_version': 3, '_deleted': true}));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #3'), findsNothing);
    expect(find.text('فاتورة #1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() =>
        InvoiceRepository.instance.upsertBuyingLocal('later', invoice(4)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream updates retain search and selected month',
      (tester) async {
    await openPage(tester);
    await tester.enterText(find.byType(TextField), 'Match');
    await tester.runAsync(() async {
      await InvoiceRepository.instance.upsertBuyingLocal('match', invoice(1));
      await InvoiceRepository.instance.upsertBuyingLocal(
          'other', invoice(2, supplierName: 'Other supplier'));
      final now = DateTime.now();
      await InvoiceRepository.instance.upsertBuyingLocal('previous-month',
          invoice(3, date: DateTime(now.year, now.month - 1, 1)));
    });
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #1'), findsOneWidget);
    expect(find.text('فاتورة #2'), findsNothing);
    expect(find.text('فاتورة #3'), findsNothing);
    await tester.runAsync(() => InvoiceRepository.instance.upsertBuyingLocal(
        'match', invoice(1, supplierName: 'Other supplier')));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة #1'), findsNothing);
    expect(find.widgetWithText(TextField, 'Match'), findsOneWidget);
  });

  testWidgets(
      'live insert during delete confirmation preserves selected invoice',
      (tester) async {
    await tester.runAsync(() async {
      await InvoiceRepository.instance
          .upsertBuyingLocal('selected', invoice(1));
      await InvoiceRepository.instance.upsertBuyingLocal('other', invoice(2));
    });
    await openPage(tester);
    final selectedCard =
        find.ancestor(of: find.text('فاتورة #1'), matching: find.byType(Card));
    await tester.tap(find.descendant(
        of: selectedCard,
        matching: find.widgetWithIcon(IconButton, Icons.delete)));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => InvoiceRepository.instance.upsertBuyingLocal('new', invoice(3)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'حذف'));
      await LocalOperationJournal.exclusive(() async {});
    });
    await tester.pumpAndSettle();
    expect(buyingInvoicesBox.containsKey('selected'), isFalse);
    expect(buyingInvoicesBox.containsKey('other'), isTrue);
    expect(buyingInvoicesBox.containsKey('new'), isTrue);
    expect(syncQueueBox.values.single.status, 'pending');
    expect(find.text('تم حذف الفاتورة بنجاح وتحديث المخزون'), findsOneWidget);
    expect(find.text('فاتورة #1'), findsNothing);
    expect(find.text('فاتورة #2'), findsOneWidget);
    expect(find.text('فاتورة #3'), findsOneWidget);
  });
}
