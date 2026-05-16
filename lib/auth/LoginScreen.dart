import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _login() async {
  final email = _emailController.text.trim();
  final password = _passwordController.text.trim();

  print('Login attempt started for email: $email');

  try {
    print('Querying Firestore for user data...');
    QuerySnapshot<Map<String, dynamic>> snapshot =
    await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      print('User document found.');
      final userData = snapshot.docs.first.data();
      if (userData['password'] == password) {
        print('Password is correct.');
        final role = userData['role'];
        print('User role is: $role');

        // Save user role to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', role);

        if (role == 'admin') {
          print('Navigating to admin home.');
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => GNavPage(),
          ));
        } else if (role == 'user') {
          print('Navigating to admin home.');
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => GNavPage(),
          ));
        }
      } else {
        print('Invalid password provided.');
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid password')));
      }
    } else {
      print('No user document found.');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User not found')));
    }
  } catch (e) {
    print('Error during login: $e');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error during login: $e')));
  }
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
                onPressed: _login,
                child: Text(
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