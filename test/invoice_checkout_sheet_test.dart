import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/Screeens/DecreaseProductComponents/invoice_checkout_sheet.dart';

void main() {
  group('sales invoice payment validation', () {
    test('missing payment method blocks saving even with exact payment', () {
      for (final method in ['', '   ']) {
        expect(
          validateInvoiceCheckoutPayment(
            paidAmount: 100,
            invoiceTotal: 100,
            paymentMethod: method,
            isReturnInvoice: false,
          ),
          'يرجى اختيار طريقة الدفع',
        );
      }
    });

    test('cash and deferred sales accept payment above the invoice total', () {
      expect(
        validateInvoiceCheckoutPayment(
          paidAmount: 120,
          invoiceTotal: 100,
          paymentMethod: 'نقداً',
          isReturnInvoice: false,
        ),
        isNull,
      );
      expect(
        validateInvoiceCheckoutPayment(
          paidAmount: 120,
          invoiceTotal: 100,
          paymentMethod: 'آجل',
          isReturnInvoice: false,
        ),
        isNull,
      );
    });

    test('payment below the invoice total requires deferred payment', () {
      expect(
        validateInvoiceCheckoutPayment(
          paidAmount: 80,
          invoiceTotal: 100,
          paymentMethod: 'نقداً',
          isReturnInvoice: false,
        ),
        contains('اختر آجل'),
      );
      expect(
        validateInvoiceCheckoutPayment(
          paidAmount: 80,
          invoiceTotal: 100,
          paymentMethod: 'آجل',
          isReturnInvoice: false,
        ),
        isNull,
      );
    });

    test('exact payment remains valid with another payment method', () {
      expect(
        validateInvoiceCheckoutPayment(
          paidAmount: 100,
          invoiceTotal: 100,
          paymentMethod: 'بطاقه',
          isReturnInvoice: false,
        ),
        isNull,
      );
    });
  });

  testWidgets('cash overpayment continues and returns the entered amount',
      (tester) async {
    final result = ValueNotifier<CheckoutSelectionResult?>(null);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(360, 690),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result.value = await showInvoiceCheckoutSheet(
                    context: context,
                    isEditing: false,
                    paymentMethod: 'نقداً',
                    invoiceDiscount: 0,
                    clientName: 'عميل اختبار',
                    clientBalance: 0,
                    notes: '',
                    originalPaidAmount: 0,
                    totalSum: 100,
                    clients: const ['عميل اختبار'],
                    isReturnInvoice: false,
                    isQuote: false,
                    isSaving: false,
                    clientExists: (_) async => true,
                    fetchClientBalance: (_) async => 0,
                  );
                },
                child: const Text('open cash checkout'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open cash checkout'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected),
        isEmpty);
    final continueButton =
        find.byKey(const Key('invoice-checkout-continue-button'));
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);
    expect(find.text('يرجى اختيار طريقة الدفع'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('invoice-paid-amount-field')),
      '120',
    );
    await tester.pump();
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);
    expect(result.value, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'نقداً'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNotNull);
    await tester.enterText(
      find.byKey(const Key('invoice-paid-amount-field')),
      '120',
    );
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(result.value?.paymentMethod, 'نقداً');
    expect(result.value?.paidAmount, 120);
    expect(find.byKey(const Key('invoice-checkout-continue-button')),
        findsNothing);
    result.dispose();
  });

  testWidgets('editing keeps the recorded payment method selected',
      (tester) async {
    CheckoutSelectionResult? result;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(360, 690),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showInvoiceCheckoutSheet(
                  context: context,
                  isEditing: true,
                  paymentMethod: 'آجل',
                  invoiceDiscount: 0,
                  clientName: 'عميل اختبار',
                  clientBalance: 0,
                  notes: '',
                  originalPaidAmount: 0,
                  totalSum: 100,
                  clients: const ['عميل اختبار'],
                  isReturnInvoice: false,
                  isQuote: false,
                  isSaving: false,
                  clientExists: (_) async => true,
                  fetchClientBalance: (_) async => 0,
                );
              },
              child: const Text('edit checkout'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('edit checkout'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'آجل'))
            .selected,
        isTrue);
    final continueButton =
        find.byKey(const Key('invoice-checkout-continue-button'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(result?.paymentMethod, 'آجل');
    expect(result?.paidAmount, 0);
  });

  testWidgets(
      'customer matches scroll and remain selectable above the keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final clients = List.generate(
        40, (index) => 'عميل ${index.toString().padLeft(2, '0')}');
    CheckoutSelectionResult? result;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(360, 800),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showInvoiceCheckoutSheet(
                  context: context,
                  isEditing: false,
                  paymentMethod: '',
                  invoiceDiscount: 0,
                  clientName: '',
                  clientBalance: 0,
                  notes: '',
                  originalPaidAmount: 0,
                  totalSum: 100,
                  clients: clients,
                  isReturnInvoice: false,
                  isQuote: false,
                  isSaving: false,
                  clientExists: (name) async => clients.contains(name),
                  fetchClientBalance: (_) async => 42,
                );
              },
              child: const Text('search customers'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('search customers'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'ابحث عن عميل أو اكتب اسم');
    await tester.ensureVisible(field);
    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.enterText(field, 'عميل');
    await tester.pumpAndSettle();
    final options = find.byType(ListView);
    expect(options, findsOneWidget);
    final bounds = tester.getRect(options);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(500));
    await tester.scrollUntilVisible(
      find.text('عميل 29'),
      150,
      scrollable:
          find.descendant(of: options, matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('عميل 29'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller?.text, 'عميل 29');
    expect(find.text('الرصيد قبل الفاتورة: 42.00 ج.م'), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final method = find.widgetWithText(ChoiceChip, 'آجل');
    await tester.ensureVisible(method);
    await tester.tap(method);
    await tester.pump();
    final continueButton =
        find.byKey(const Key('invoice-checkout-continue-button'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(result?.clientName, 'عميل 29');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'payment breakdown shows its total and can populate the paid amount',
      (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(360, 690),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showInvoiceCheckoutSheet(
                    context: context,
                    isEditing: false,
                    paymentMethod: 'آجل',
                    invoiceDiscount: 0,
                    clientName: '',
                    clientBalance: 0,
                    notes: '',
                    originalPaidAmount: 0,
                    totalSum: 500,
                    clients: const [],
                    isReturnInvoice: false,
                    isQuote: false,
                    isSaving: false,
                    clientExists: (_) async => true,
                    fetchClientBalance: (_) async => 0,
                  );
                },
                child: const Text('open checkout'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open checkout'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('invoice-breakdown-wallet-field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-breakdown-cash-field')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-breakdown-instapay-field')),
      '30',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-breakdown-bank-field')),
      '40',
    );
    await tester.pump();

    expect(find.text('100.00 ج.م'), findsOneWidget);
    expect(
        find.textContaining('المدفوع لا يطابق إجمالي التوزيع'), findsOneWidget);

    final applyButton = find.byKey(const Key('apply-payment-breakdown-total'));
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pump();

    final paidField = tester.widget<TextField>(
      find.byKey(const Key('invoice-paid-amount-field')),
    );
    expect(paidField.controller?.text, '100.00');
    expect(
        find.textContaining('المدفوع لا يطابق إجمالي التوزيع'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('invoice-paid-amount-field')),
      '80',
    );
    await tester.pump();
    expect(
        find.textContaining('المدفوع لا يطابق إجمالي التوزيع'), findsOneWidget);
    expect(find.textContaining('الفرق: 20 ج.م'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
