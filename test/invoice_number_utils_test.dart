import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/Services/invoice_number_utils.dart';

void main() {
  group('invoiceLineUnitPrice', () {
    test('uses the current selectedPrice field', () {
      expect(
        invoiceLineUnitPrice({
          'selectedPrice': '685',
          'amount': 3,
          'total': 2055,
        }),
        685,
      );
    });

    test('supports the legacy price field', () {
      expect(invoiceLineUnitPrice({'price': 660}), 660);
    });

    test('derives a missing or zero price from total and quantity', () {
      expect(
        invoiceLineUnitPrice({
          'selectedPrice': 0,
          'amount': 6,
          'total': 690,
        }),
        115,
      );
    });

    test('reverses a percentage discount when deriving the unit price', () {
      expect(
        invoiceLineUnitPrice({
          'amount': 2,
          'total': 180,
          'discount': 10,
          'discountIsPercent': true,
        }),
        100,
      );
    });

    test('reverses a fixed discount when deriving the unit price', () {
      expect(
        invoiceLineUnitPrice({
          'amount': 2,
          'total': 180,
          'discount': 20,
          'discountIsPercent': false,
        }),
        100,
      );
    });

    test('returns zero when neither price nor a valid quantity is available',
        () {
      expect(invoiceLineUnitPrice({'amount': 0, 'total': 100}), 0);
    });
  });
}
