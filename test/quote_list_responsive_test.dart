import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Screeens/QuoteListPage.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/quote_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quote_responsive_');
    await initHive(directory: directory.path);

    final quote = QuoteLocal(
      id: 'quote-1',
      clientName: 'عميل باسم طويل لاختبار شاشة الهاتف الصغيرة',
      clientId: 'client-1',
      date: DateTime(2026, 9, 29, 12, 30),
      totalSum: 12345.75,
      paidAmount: 1200,
      invoiceDiscount: 125,
      notes: 'ملاحظات طويلة للتأكد من التفاف النص بصورة صحيحة',
      createdAt: DateTime(2026, 9, 29, 12, 30),
    );
    quote.products = [
      {
        'product': 'منتج طويل الاسم لاختبار العرض على الهاتف',
        'amount': 12,
        'selectedPrice': 950.5,
        'discount': 25,
        'total': 11381,
      },
      {
        'product': 'منتج ثان',
        'amount': 2,
        'selectedPrice': 482.375,
        'discount': 0,
        'total': 964.75,
      },
    ];
    await quotesBox.put(quote.id, quote);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('quote card fits and remains readable at 320 logical pixels',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 690);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(320, 690),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: QuoteListPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تنفيذ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('عميل باسم طويل لاختبار شاشة الهاتف الصغيرة'));
    await tester.pumpAndSettle();

    expect(find.textContaining('إجمالي الكمية'), findsOneWidget);
    expect(find.textContaining('المتبقي من الفاتورة'), findsOneWidget);
    expect(
        find.text('منتج طويل الاسم لاختبار العرض على الهاتف'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
