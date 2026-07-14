import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'Screeens/SplashScreen.dart';
import 'firebase_options.dart';
import 'Widgets/app_responsive.dart';
import 'Widgets/responsive_screen_util_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
