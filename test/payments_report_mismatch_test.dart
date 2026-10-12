import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Widgets/payment_breakdown_mismatch_hint.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/payment_breakdown_local.dart';
import 'package:kareem_store/reports/PaymentsReportPage.dart';
import 'package:kareem_store/repositories/invoice_repository.dart';
import 'package:kareem_store/repositories/payment_breakdown_repository.dart';

void main() {
  late Directory directory;
  final mismatch = find.textContaining('المدفوع لا يطابق إجمالي التوزيع');

  Map<String, dynamic> invoice(double paid) => {
        'invoiceNumber': 1,
        'date': DateTime.now(),
        'clientName': 'Hint customer',
        'totalSum': 100.0,
        'paidAmount': paid,
        'products': [],
      };

  PaymentBreakdownLocal breakdown(
          {String invoiceId = 'sale', double cash = 80}) =>
      PaymentBreakdownLocal(
        id: 'distribution',
        date: DateTime.now(),
        timestamp: DateTime.now(),
        invoiceId: invoiceId,
        invoiceNumber: '1',
        clientName: 'Hint customer',
        cash: cash,
      );

  Future<void> openReport(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(800, 600),
      builder: (_, __) => const MaterialApp(home: PaymentsReportPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reload(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('payment_mismatch_');
    await initHive(directory: directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('report hint follows both invoice payment and distribution edits',
      (tester) async {
    await tester.runAsync(() async {
      await InvoiceRepository.instance.upsertSaleLocal('sale', invoice(100));
      await PaymentBreakdownRepository.instance.upsertLocal(breakdown());
    });
    await openReport(tester);
    expect(mismatch, findsOneWidget);
    expect(find.textContaining('الفرق: 20 ج.م'), findsOneWidget);
    await tester.runAsync(
        () => InvoiceRepository.instance.upsertSaleLocal('sale', invoice(80)));
    await reload(tester);
    expect(mismatch, findsNothing);
    await tester.runAsync(() =>
        PaymentBreakdownRepository.instance.upsertLocal(breakdown(cash: 60)));
    await reload(tester);
    expect(mismatch, findsOneWidget);
    await tester.tap(find.byTooltip('تعديل'));
    await tester.pumpAndSettle();
    expect(mismatch, findsNWidgets(2));
    await tester.enterText(find.widgetWithText(TextField, 'نقدي'), '80');
    await tester.pump();
    // Only the report card remains mismatched until this edit is saved.
    expect(mismatch, findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unlinked and not-yet-downloaded invoices do not show false hints',
      (tester) async {
    await tester.runAsync(() => PaymentBreakdownRepository.instance
        .upsertLocal(breakdown(invoiceId: '')));
    await openReport(tester);
    expect(mismatch, findsNothing);
    await tester.runAsync(() => PaymentBreakdownRepository.instance
        .upsertLocal(breakdown(invoiceId: 'return')));
    await reload(tester);
    expect(mismatch, findsNothing);
    await tester.runAsync(() =>
        InvoiceRepository.instance.upsertReturnLocal('return', invoice(100)));
    await reload(tester);
    expect(mismatch, findsOneWidget);
  });

  testWidgets('currency rounding does not flag equal amounts', (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(800, 600),
      builder: (_, __) => const MaterialApp(
        home: Scaffold(
          body: PaymentBreakdownMismatchHint(
              paidAmount: 0.3, breakdownTotal: 0.1 + 0.2),
        ),
      ),
    ));
    expect(mismatch, findsNothing);
  });
}
