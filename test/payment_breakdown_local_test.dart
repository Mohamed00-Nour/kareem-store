import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/local_db/models/payment_breakdown_local.dart';

void main() {
  test('payment breakdown keeps its invoice and client identity', () {
    final entry = PaymentBreakdownLocal.fromFirestore('payment_invoice-1', {
      'date': '2026-09-10T10:30:00.000',
      'wallet': 100,
      'cash': 50.5,
      'instapay': 25,
      'bankTransfer': 10,
      'notes': 'invoice payment distribution',
      'timestamp': '2026-09-10T10:31:00.000',
      'invoiceId': 'invoice-1',
      'invoiceNumber': '42',
      'clientName': 'عميل تجريبي',
    });

    expect(entry.invoiceId, 'invoice-1');
    expect(entry.invoiceNumber, '42');
    expect(entry.clientName, 'عميل تجريبي');
    expect(entry.wallet, 100);
    expect(entry.cash, 50.5);

    final serialized = entry.toFirestore();
    expect(serialized['invoiceId'], 'invoice-1');
    expect(serialized['invoiceNumber'], '42');
    expect(serialized['clientName'], 'عميل تجريبي');
  });

  test('older payment breakdowns remain readable without linked fields', () {
    final entry = PaymentBreakdownLocal.fromFirestore('legacy-payment', {
      'date': '2026-09-10T10:30:00.000',
      'cash': 75,
      'timestamp': '2026-09-10T10:31:00.000',
    });

    expect(entry.invoiceId, isEmpty);
    expect(entry.invoiceNumber, isEmpty);
    expect(entry.clientName, isEmpty);
    expect(entry.cash, 75);
  });
}
