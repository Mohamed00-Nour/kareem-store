import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../Services/bluetooth_permission_service.dart';
import '../auth/LoginScreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )
      ..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareApp());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _prepareApp() async {
    try {
      await Future.wait([
        Future.delayed(const Duration(seconds: 3)),
        BluetoothPermissionService.ensureOnAppStart(context),
      ]);
    } catch (e) {
      // Ignored
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: ScaleTransition(
              scale: _animation,
              child: Image.asset(
                'assets/images/tools_7307974.png',
                width: 160.w,
                height: 160.h,
              ),
            ),
          ),
          Center(
            child: ScaleTransition(
              scale: _animation,
              child: Text(
                'أبو مجدي للحدايد والعدد',
                style: TextStyle(fontSize: 24.sp),
              ),
            ),
          ),
        ],
      ),
    );
  }
}