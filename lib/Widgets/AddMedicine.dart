import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/Employee.dart';

class AddMedicine extends StatefulWidget {
  final Employee employee;

  const AddMedicine({super.key, required this.employee});

  @override
  _AddMedicineState createState() => _AddMedicineState();
}

class _AddMedicineState extends State<AddMedicine> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  void dispose() {
    _dateController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _addMedicine() async {
    if (_formKey.currentState!.validate()) {
      final medicine = Medicine(
        id: FirebaseFirestore.instance.collection('employees').doc().id, // Generate unique id
        employeeId: widget.employee.id,
        employeeName: widget.employee.name,
        date: _dateController.text,
        responsible: widget.employee.name, // Use employee name as responsible
        value: _valueController.text,
      );

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employee.id)
          .update({
        'medicines': FieldValue.arrayUnion([medicine.toMap()])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إضافة العلاج بنجاح')),
      );

      _formKey.currentState!.reset();
      _dateController.clear();
      _valueController.clear();
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
            textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black),
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
                  padding: EdgeInsets.all(5.w),
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
                        return 'من فضلك أدخل التاريخ';
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
                  padding: EdgeInsets.all(5.w),
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
                        return 'من فضلك أدخل المبلغ';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              ElevatedButton(
                onPressed: _addMedicine,
                style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    backgroundColor: Colors.black.withOpacity(0.7)),
                child: Text(
                  'حفظ',
                  style: TextStyle(
                    fontSize: 18.sp,
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