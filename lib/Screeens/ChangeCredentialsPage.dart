import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChangeCredentialsPage extends StatefulWidget {
  const ChangeCredentialsPage({super.key});

  @override
  State<ChangeCredentialsPage> createState() => _ChangeCredentialsPageState();
}

class _ChangeCredentialsPageState extends State<ChangeCredentialsPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String _currentEmail = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allUsers = [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _loadUsersData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsersData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentEmail = prefs.getString('user_email') ?? '';

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      setState(() {
        _allUsers = snapshot.docs;
        if (_allUsers.isNotEmpty) {
          // Pre-select the logged-in user's account if it exists in the list
          final index = _allUsers.indexWhere(
              (doc) => (doc.data()['email'] ?? '') == _currentEmail);
          if (index != -1) {
            _selectedUserId = _allUsers[index].id;
            _emailController.text = _allUsers[index].data()['email'] ?? '';
          } else {
            _selectedUserId = _allUsers.first.id;
            _emailController.text = _allUsers.first.data()['email'] ?? '';
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل بيانات المستخدمين: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم اختيار حساب لتعديله')),
      );
      return;
    }

    final selectedDoc = _allUsers.firstWhere((d) => d.id == _selectedUserId);
    final userData = selectedDoc.data();
    final dbPassword = userData['password']?.toString().trim() ?? '';
    final oldEmail = userData['email']?.toString().trim() ?? '';

    setState(() => _isLoading = true);

    final newEmail = _emailController.text.trim();
    final newPassword = _passwordController.text.isNotEmpty
        ? _passwordController.text.trim()
        : dbPassword;

    try {
      // If email has changed, verify if new email already exists in collection under another doc
      if (newEmail != oldEmail) {
        final existingQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: newEmail)
            .limit(1)
            .get();
        if (existingQuery.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا البريد الإلكتروني مستخدم بالفعل')),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      // Update in Firestore
      await selectedDoc.reference.update({
        'email': newEmail,
        'password': newPassword,
      });

      // If we updated the currently logged-in user, update SharedPreferences
      if (oldEmail == _currentEmail) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', newEmail);
        _currentEmail = newEmail;
      }

      // Refresh local user list in case email changed
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      setState(() {
        _allUsers = snapshot.docs;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث البيانات بنجاح')),
        );
        // Clear password fields on success
        _passwordController.clear();
        _confirmPasswordController.clear();
      }
    } catch (e) {

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحديث البيانات: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.black54, fontSize: 14.sp),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: const BorderSide(color: Colors.orange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'تغيير بيانات الحساب',
            style: TextStyle(fontSize: 20.sp, color: Colors.white),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading && _allUsers.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Colors.orange))
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Icon(
                          Icons.security,
                          size: 70.sp,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      Text(
                        'اختر الحساب من القائمة لتعديل البريد الإلكتروني وكلمة المرور الخاصة به.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                      ),
                      SizedBox(height: 25.h),

                      // Dropdown Selector
                      DropdownButtonFormField<String>(
                        decoration: _buildInputDecoration('اختر الحساب المراد تعديله'),
                        value: _selectedUserId,
                        items: _allUsers.map((doc) {
                          final data = doc.data();
                          final email = data['email'] ?? '';
                          final role = data['role'] ?? '';
                          final roleLabel = role == 'admin' ? 'مسؤول (admin)' : 'مستخدم (user)';
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text('$email ($roleLabel)'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedUserId = val;
                            final selectedDoc = _allUsers.firstWhere((d) => d.id == val);
                            _emailController.text = selectedDoc.data()['email'] ?? '';
                            _passwordController.clear();
                            _confirmPasswordController.clear();
                          });
                        },
                      ),
                      SizedBox(height: 20.h),

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _buildInputDecoration('البريد الإلكتروني الجديد'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال البريد الإلكتروني';
                          }
                          return null;
                        },
                      ),
                      const Divider(height: 32, thickness: 1),

                      // New Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: _buildInputDecoration('كلمة المرور الجديدة (اختياري)'),
                        validator: (value) {
                          if (value != null && value.isNotEmpty && value.length < 6) {
                            return 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16.h),

                      // Confirm Password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: _buildInputDecoration('تأكيد كلمة المرور الجديدة'),
                        validator: (value) {
                          if (_passwordController.text.isNotEmpty &&
                              value != _passwordController.text) {
                            return 'كلمات المرور الجديدة غير متطابقة';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 30.h),

                      // Save Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          textStyle: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isLoading ? null : _updateCredentials,
                        child: _isLoading
                            ? SizedBox(
                                width: 20.w,
                                height: 20.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('حفظ التغييرات'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
