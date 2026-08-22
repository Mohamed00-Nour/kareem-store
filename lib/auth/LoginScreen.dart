import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screeens/g_Nav.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail =
          prefs.getString('saved_email') ?? prefs.getString('user_email') ?? '';
      final savedPassword = prefs.getString('saved_password') ?? '';
      if (mounted) {
        setState(() {
          if (savedEmail.isNotEmpty) _emailController.text = savedEmail;
          if (savedPassword.isNotEmpty)
            _passwordController.text = savedPassword;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Do a live connectivity check instead of reading the cached flag,
      // which may still be false if the app just started (race condition).
      final connectivityResult = await Connectivity().checkConnectivity();
      final bool isOnline = connectivityResult is List
          ? (connectivityResult as List).any((r) => r != ConnectivityResult.none)
          : connectivityResult != ConnectivityResult.none;

      if (isOnline) {
        try {
          QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
              .instance
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 8));

          if (snapshot.docs.isNotEmpty) {
            final userData = snapshot.docs.first.data();
            if (userData['password'] == password) {
              final role = userData['role']?.toString() ?? 'admin';
              await _saveSessionAndNavigate(email, password, role);
              return;
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid password')),
                );
              }
              return;
            }
          }
        } catch (_) {
          // Network query timed out or failed — fall through to offline check
        }
      }

      // Offline Login Verification via saved credentials
      final prefs = await SharedPreferences.getInstance();
      final savedEmail =
          prefs.getString('saved_email') ?? prefs.getString('user_email') ?? '';
      final savedPassword = prefs.getString('saved_password') ?? '';
      final savedRole = prefs.getString('user_role') ?? 'admin';

      if (savedEmail.isNotEmpty &&
          email.toLowerCase() == savedEmail.toLowerCase()) {
        if (password == savedPassword) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Logged in locally (Offline mode)')),
            );
          }
          await _saveSessionAndNavigate(email, password, savedRole);
          return;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid password')),
            );
          }
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOnline
                ? 'User not found'
                : 'Offline mode: Please connect to the internet for initial login'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during login: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSessionAndNavigate(
      String email, String password, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('user_email', email);
    await prefs.setString('saved_email', email);
    await prefs.setString('saved_password', password);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => GNavPage()),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[200],
      contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 15.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide.none,
      ),
    );
  }

  ButtonStyle _buildButtonStyle() {
    return ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.blueAccent,
      padding: EdgeInsets.symmetric(vertical: 15.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.r),
      ),
      textStyle: TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 60.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/tools_7307974.png',
              width: 130.w,
              height: 130.h,
            ),
            SizedBox(height: 40.h),
            TextField(
              controller: _emailController,
              decoration: _buildInputDecoration('Email'),
            ),
            SizedBox(height: 20.h),
            TextField(
              controller: _passwordController,
              decoration: _buildInputDecoration('Password'),
              obscureText: true,
            ),
            SizedBox(height: 30.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: _buildButtonStyle(),
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Login',
                        style: TextStyle(fontSize: 16.sp),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
