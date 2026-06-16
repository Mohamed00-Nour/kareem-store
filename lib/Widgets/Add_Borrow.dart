import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/Employee.dart';

class AddBorrow extends StatefulWidget {
  final Employee employee;

  const AddBorrow({super.key, required this.employee});

  @override
  _AddBorrowState createState() => _AddBorrowState();
}

class _AddBorrowState extends State<AddBorrow> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _responsibleController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  void dispose() {
    _dateController.dispose();
    _responsibleController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _addBorrow() async {
    if (_formKey.currentState!.validate()) {
      final borrow = Borrow(
        id: FirebaseFirestore.instance.collection('employees').doc().id, // Generate unique id
        employeeId: widget.employee.id,
        employeeName: widget.employee.name,
        date: _dateController.text,
        responsible: _responsibleController.text,
        value: _valueController.text,
      );

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employee.id)
          .update({
        'borrows': FieldValue.arrayUnion([borrow.toMap()])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Borrow data added successfully')),
      );

      _formKey.currentState!.reset();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final int currentYear = DateTime.now().year;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(currentYear, 1, 1),
      lastDate: DateTime(currentYear, 12, 31),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.orange.withOpacity(0.7),
            hintColor: Colors.orange.withOpacity(0.7),
            colorScheme: const ColorScheme.light(primary: Colors.orange),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.symmetric(vertical: 15.h, horizontal: 25.w),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Card(
                margin: EdgeInsets.all(8.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month),
                      hintText: 'أدخل التاريخ',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    readOnly: true,
                    onTap: () => _selectDate(context),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter date';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.all(8.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    keyboardType: TextInputType.text,
                    controller: _responsibleController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.perm_identity_outlined),
                      hintText: 'أدخل إسم المسؤول',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the responsible person\'s name';
                      }
                      final validRegExp = RegExp(r'^[a-zA-Z\u0600-\u06FF\s]+$');
                      if (!validRegExp.hasMatch(value)) {
                        return 'Please enter only Arabic or English characters and spaces';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.all(8.w),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: TextFormField(
                    keyboardType: TextInputType.number,
                    controller: _valueController,
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.attach_money_outlined),
                      labelStyle: TextStyle(
                        color: Colors.black,
                      ),
                      hintText: 'أدخل المبلغ',
                      border: InputBorder.none,
                    ),
                    textAlign: TextAlign.center,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter value';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              ElevatedButton(
                onPressed: _addBorrow,
                style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    backgroundColor: Colors.black.withOpacity(0.7)),
                child: Text(
                  'حفظ',
                  style: TextStyle(
                    fontSize: 20.sp,
                    color: Colors.white.withOpacity(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}