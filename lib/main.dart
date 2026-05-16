import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'Screeens/SplashScreen.dart';
import 'Services/app_error_logger.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  AppErrorLogger.installGlobalHandlers();

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      AppErrorLogger.record(
        error: error,
        stackTrace: stack,
        step: 'uncaught_async',
        severity: AppErrorSeverity.fatal,
      );
    },
  );
}


class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return  ScreenUtilInit(
      designSize: const Size(360, 690), // Set the design size of your app
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
          theme: ThemeData(
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.black.withOpacity(0.8),
            ),
          ),
          debugShowCheckedModeBanner: false,
          title: 'Kareem Store',
          home: SplashScreen(),
        );
      },
    );
  }
}