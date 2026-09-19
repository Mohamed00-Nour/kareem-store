import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/Services/client_invoice_running_balance_service.dart';

void main() {
  test('computes the same chronological balances shown on the client page', () {
    final firstSale = <String, dynamic>{
      'date': DateTime(2026, 9, 10, 9),
      'totalSum': 4710,
      'paidAmount': 0,
    };
    final targetSale = <String, dynamic>{
      'date': DateTime(2026, 9, 12, 9, 21),
      'totalSum': 1410,
      'paidAmount': 0,
    };

    ClientInvoiceRunningBalanceService.apply(
      salesInvoices: [firstSale, targetSale],
      returnInvoices: const [],
      payments: const [],
    );

    expect(targetSale['_computedPrevBalance'], 4710);
    expect(targetSale['_computedRemainingOwed'], 6120);
  });

  test('includes returns and manual payments but not invoice payment entries',
      () {
    final sale = <String, dynamic>{
      'date': DateTime(2026, 9, 10),
      'totalSum': 1000,
      'paidAmount': 200,
    };
    final invoicePayment = <String, dynamic>{
      'timestamp': DateTime(2026, 9, 10, 1),
      'type': 'sale_payment',
      'enteredBalance': 200,
    };
    final manualPayment = <String, dynamic>{
      'timestamp': DateTime(2026, 9, 11),
      'type': 'deduction',
      'enteredBalance': 100,
    };
    final saleReturn = <String, dynamic>{
      'date': DateTime(2026, 9, 12),
      'totalSum': 50,
      'paidAmount': 0,
    };

    ClientInvoiceRunningBalanceService.apply(
      salesInvoices: [sale],
      returnInvoices: [saleReturn],
      payments: [invoicePayment, manualPayment],
    );

    expect(sale['_computedRemainingOwed'], 800);
    expect(manualPayment['_computedPrevBalance'], 800);
    expect(manualPayment['_computedRemainingOwed'], 700);
    expect(saleReturn['_computedPrevBalance'], 700);
    expect(saleReturn['_computedRemainingOwed'], 650);
  });
}
