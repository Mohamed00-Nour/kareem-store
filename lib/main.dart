import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'Screeens/SplashScreen.dart';
import 'firebase_options.dart';
import 'Widgets/app_responsive.dart';
import 'Widgets/responsive_screen_util_host.dart';
import 'local_db/hive_init.dart';
import 'sync/connectivity_service.dart';
import 'sync/realtime_sync_service.dart';
import 'sync/sync_queue_manager.dart';
import 'Services/printer_settings_service.dart';
import 'Services/customer_balance_store.dart';
import 'Services/supplier_balance_store.dart';
import 'sync/local_operation_journal.dart';

Future<void> main() async {
  //9.38
  WidgetsFlutterBinding.ensureInitialized();
  final startupTimer = Stopwatch()..start();
  var startupStage = 'opening local Hive boxes';
  try {
    await initHive(); // Initialize local Hive database first
    debugPrint('Startup Hive complete: ${startupTimer.elapsedMilliseconds} ms');
    // Recover durable uploads interrupted by a previous app shutdown before any
    // startup service can make the first queue-processing attempt.
    startupStage = 'recovering interrupted local saves';
    await LocalOperationJournal.recover();
    debugPrint(
        'Startup journal complete: ${startupTimer.elapsedMilliseconds} ms');
    startupStage = 'restoring customer balance mirrors';
    await CustomerBalanceStore.preserveExistingBalances();
    await SupplierBalanceStore.preserveExistingBalances();
    debugPrint(
        'Startup balances complete: ${startupTimer.elapsedMilliseconds} ms');
    startupStage = 'recovering interrupted uploads';
    await SyncQueueManager.instance.recoverInterruptedItems();
    debugPrint(
        'Startup queue complete: ${startupTimer.elapsedMilliseconds} ms');
  } catch (error, stackTrace) {
    debugPrint('Startup failed during $startupStage: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(MaterialApp(
        home: Scaffold(
      appBar: AppBar(title: const Text('تعذر فتح البيانات المحلية')),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Text(
                'تم الاحتفاظ بملفات البيانات والعمليات المعلقة. لم يتم حذفها. '
                'أعد المحاولة أو راجع نسخة احتياطية مع الدعم.'),
            SelectableText('$startupStage: $error'),
            ElevatedButton(
                onPressed: main, child: const Text('إعادة المحاولة')),
          ])),
    )));
    return;
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint(
      'Startup Firebase complete: ${startupTimer.elapsedMilliseconds} ms');
  // Pre-load cached settings (appbar title/logo) from SharedPreferences
  await PrinterSettingsService.initLocalCache();
  debugPrint(
      'Startup settings complete: ${startupTimer.elapsedMilliseconds} ms');
  runApp(const MyApp());
  // Start network work after the first local frame. It is background hydration
  // and upload; neither should delay showing data already available in Hive.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('Startup first frame: ${startupTimer.elapsedMilliseconds} ms');
    ConnectivityService.instance.startListening();
    RealtimeSyncService.instance.startListening();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenUtilHost(
      builder: (context) {
        return MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
          theme: ThemeData(
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.black.withOpacity(0.8),
            ),
          ),
          debugShowCheckedModeBanner: false,
          title: 'أبو مجدي للحدايد والعدد',
          builder: (context, child) {
            return ResponsiveAppShell(
              child: Directionality(
                textDirection: ui.TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
