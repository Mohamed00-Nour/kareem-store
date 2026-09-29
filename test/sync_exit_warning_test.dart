import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kareem_store/sync/ui/sync_exit_dialog.dart';

void main() {
  Future<ValueNotifier<bool?>> openExitDialog(
    WidgetTester tester, {
    required bool uploading,
    int unfinishedCount = 1,
  }) async {
    final result = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(360, 690),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result.value = await showSyncAwareExitDialog(
                  context,
                  uploading: uploading,
                  unfinishedCount: unfinishedCount,
                );
              },
              child: const Text('exit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('active upload offers wait and keeps the application open',
      (tester) async {
    final result = await openExitDialog(
      tester,
      uploading: true,
      unfinishedCount: 3,
    );

    expect(find.textContaining('يوجد 3 عملية جارٍ رفعها'), findsOneWidget);
    expect(find.text('البقاء حتى اكتمال الرفع'), findsOneWidget);
    expect(find.text('إغلاق الآن'), findsOneWidget);

    await tester.tap(find.text('البقاء حتى اكتمال الرفع'));
    await tester.pumpAndSettle();

    expect(result.value, isFalse);
  });

  testWidgets('active upload can be closed explicitly', (tester) async {
    final result = await openExitDialog(tester, uploading: true);

    await tester.tap(find.text('إغلاق الآن'));
    await tester.pumpAndSettle();

    expect(result.value, isTrue);
  });

  testWidgets('no active upload uses the normal exit question', (tester) async {
    await openExitDialog(tester, uploading: false, unfinishedCount: 2);

    expect(find.text('هل تريد حقا الخروج من التطبيق ؟'), findsOneWidget);
    expect(find.text('البقاء حتى اكتمال الرفع'), findsNothing);
    expect(find.text('إغلاق الآن'), findsNothing);
  });
}
