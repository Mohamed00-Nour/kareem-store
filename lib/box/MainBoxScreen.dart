import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'BoxChangesScreen.dart';

class MainBoxScreen extends StatefulWidget {
  const MainBoxScreen({Key? key}) : super(key: key);

  @override
  _MainBoxScreenState createState() => _MainBoxScreenState();
}

class _MainBoxScreenState extends State<MainBoxScreen> {
  double _boxValue = 0.0;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchBoxValue();
  }

  Future<void> _fetchBoxValue() async {
    DocumentSnapshot boxDoc =
        await FirebaseFirestore.instance.collection('box').doc('mainBox').get();

    if (boxDoc.exists) {
      setState(() {
        _boxValue = (boxDoc['value'] ?? 0.0).toDouble();
      });
    }
  }

  Future<void> _updateBoxValue(double value, String type,
      {String? name}) async {
    try {
      DocumentReference boxDocRef =
          FirebaseFirestore.instance.collection('box').doc('mainBox');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot boxSnapshot = await transaction.get(boxDocRef);

        if (boxSnapshot.exists) {
          double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
          double newBoxValue = type == 'addition'
              ? currentBoxValue + value
              : currentBoxValue - value;

          transaction.update(boxDocRef, {'value': newBoxValue});

          // Add change to the subcollection
          await boxDocRef.collection('changes').add({
            'date': _selectedDate,
            'value': value,
            'type': type,
            if (name != null) 'name': name,
          });
        }
      });

      _fetchBoxValue();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الصندوق بنجاح')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showAddDialog() {
    final TextEditingController valueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة إلى الصندوق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              decoration: const InputDecoration(hintText: 'أدخل القيمة'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            TextButton(
              onPressed: _pickDate,
              child: Text(
                'التاريخ: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              double value = double.tryParse(valueController.text) ?? 0.0;
              if (value > 0) {
                _updateBoxValue(value, 'addition');
                Navigator.pop(context);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showDecreaseDialog() {
    final TextEditingController valueController = TextEditingController();
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صرف من الصندوق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueController,
              decoration: const InputDecoration(hintText: 'أدخل القيمة'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'اسم المصروف'),
            ),
            TextButton(
              onPressed: _pickDate,
              child: Text(
                'التاريخ: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              double value = double.tryParse(valueController.text) ?? 0.0;
              String name = nameController.text.trim();
              if (value > 0 && name.isNotEmpty) {
                _updateBoxValue(value, 'decrement', name: name);
                Navigator.pop(context);
              }
            },
            child: const Text('صرف'),
          ),
        ],
      ),
    );
  }

  void _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصندوق الرئيسي',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            )),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'قيمة الصندوق: ${_boxValue.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _showAddDialog,
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.green.withOpacity(0.7)),
                  child: Text('إضافة', style: TextStyle(color: Colors.white, fontSize: 18.sp),),
                ),
                ElevatedButton(
                  onPressed: _showDecreaseDialog,
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.red.withOpacity(0.7)),
                  child: Text(
                    'صرف',
                    style: TextStyle(color: Colors.white, fontSize: 18.sp),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            ElevatedButton(
              onPressed: //push Navigate to BoxChangesScreen
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BoxChangesScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.7)),
              child: Text(
                'التغيرات',
                style: TextStyle(color: Colors.white, fontSize: 18.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
