import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/Screeens/DecreaseProductComponents/invoice_checkout_sheet.dart';

void main() {
  group('sales invoice payment validation', () {
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
    await tester.enterText(
      find.byKey(const Key('invoice-paid-amount-field')),
      '120',
    );

    final continueButton =
        find.byKey(const Key('invoice-checkout-continue-button'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(result.value?.paymentMethod, 'نقداً');
    expect(result.value?.paidAmount, 120);
    expect(find.byKey(const Key('invoice-checkout-continue-button')),
        findsNothing);
    result.dispose();
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

    final applyButton = find.byKey(const Key('apply-payment-breakdown-total'));
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pump();

    final paidField = tester.widget<TextField>(
      find.byKey(const Key('invoice-paid-amount-field')),
    );
    expect(paidField.controller?.text, '100.00');
    expect(tester.takeException(), isNull);
  });
}
