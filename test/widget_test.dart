import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    expect(const MyApp(), isNotNull);
  });
}
