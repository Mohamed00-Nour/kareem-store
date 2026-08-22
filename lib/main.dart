import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'Screeens/SplashScreen.dart';
import 'firebase_options.dart';
import 'Widgets/app_responsive.dart';
import 'Widgets/responsive_screen_util_host.dart';
import 'local_db/hive_init.dart';
import 'repositories/data_sync_service.dart';
import 'sync/connectivity_service.dart';
import 'sync/realtime_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive(); // Initialize local Hive database first
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Kick off background cache sync — fails silently if offline
  DataSyncService.instance.syncOnStartup();
  // Start connectivity listener — auto-syncs queue when internet returns
  ConnectivityService.instance.startListening();
  // Start real-time Firestore stream listener — streams stock & invoice changes to Hive across devices immediately
  RealtimeSyncService.instance.startListening();
  runApp(const MyApp());
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
