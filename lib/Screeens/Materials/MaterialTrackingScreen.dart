import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MaterialTrackingScreen extends StatefulWidget {
  final List<String> materials;

  const MaterialTrackingScreen({super.key, required this.materials});

  @override
  _MaterialTrackingScreenState createState() => _MaterialTrackingScreenState();
}

class _MaterialTrackingScreenState extends State<MaterialTrackingScreen> {
  final List<String> _departments = ['السحب', 'الحقن'];
  final List<String> _supervisorsSahb = ['يحيي ذكريا', 'عمرو قرني', 'محمد رمضان'];
  final List<String> _supervisorsHaqn = ['سيد عوض', 'أيمن صلاح', 'عبدالرحمن عزوز', 'محمد علي'];
  String? _selectedDepartment;
  String? _selectedSupervisor;
  String? _selectedMaterial;
  DateTime? _selectedDate;
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _leftAmountController = TextEditingController();
  final TextEditingController _productAmountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  void _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
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
        _selectedDate = picked;
        _dateController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  void _calculateDeadMaterials() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final int initialAmount = int.parse(_amountController.text);
      final int leftAmount = int.parse(_leftAmountController.text);
      final int productAmount = int.parse(_productAmountController.text);
      final int deadMaterials = initialAmount - (leftAmount + productAmount);
      final double rate = (productAmount / initialAmount) * 100;

      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('materials')
          .where('material', isEqualTo: _selectedMaterial)
          .get();

      if (query.docs.isNotEmpty) {
        for (var doc in query.docs) {
          int existingAmount = int.parse(doc['amount']);
          int newAmount = existingAmount - initialAmount;
          await FirebaseFirestore.instance
              .collection('materials')
              .doc(doc.id)
              .update({'amount': newAmount.toString()});

          await FirebaseFirestore.instance
              .collection('materials')
              .doc(doc.id)
              .collection('history')
              .add({
            'date': _selectedDate,
            'amount': initialAmount,
            'leftAmount': leftAmount,
            'productAmount': productAmount,
            'deadMaterials': deadMaterials,
            'supervisor': _selectedSupervisor,
            'department': _selectedDepartment,
          });

          await FirebaseFirestore.instance
              .collection('materials')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': _selectedDate,
            'amount': initialAmount,
            'type': 'decrease',
          });

          await FirebaseFirestore.instance
              .collection('supervisors')
              .doc(_selectedSupervisor)
              .collection('history')
              .add({
            'date': _selectedDate,
            'material': _selectedMaterial,
            'amount': initialAmount,
            'leftAmount': leftAmount,
            'productAmount': productAmount,
            'deadMaterials': deadMaterials,
            'department': _selectedDepartment,
            'rate': rate,
          });

          await FirebaseFirestore.instance
              .collection('supervisors')
              .doc(_selectedSupervisor)
              .set({
            'rate': FieldValue.increment(rate),
          }, SetOptions(merge: true));
        }
      }

      setState(() {
        _isLoading = false;
      });

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('نتائج التتبع'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('كمية الهالك: $deadMaterials'),
                Text('النسبة: ${rate.toStringAsFixed(2)}%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تتبع الخامات', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(10.w),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: TextFormField(
                          controller: _dateController,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.calendar_today),
                            hintText: 'اختر التاريخ',
                            border: InputBorder.none,
                          ),
                          readOnly: true,
                          onTap: _pickDate,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار التاريخ';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.business),
                            hintText: 'اختر القسم',
                            border: InputBorder.none,
                          ),
                          value: _selectedDepartment,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedDepartment = newValue;
                              _selectedSupervisor = null;
                            });
                          },
                          items: _departments.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار القسم';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.person),
                            hintText: 'اختر المشرف',
                            border: InputBorder.none,
                          ),
                          value: _selectedSupervisor,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupervisor = newValue;
                            });
                          },
                          items: (_selectedDepartment == 'السحب' ? _supervisorsSahb : _supervisorsHaqn)
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار المشرف';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.shopping_cart),
                            hintText: 'اختر المادة',
                            border: InputBorder.none,
                          ),
                          value: _selectedMaterial,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedMaterial = newValue;
                            });
                          },
                          items: widget.materials.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار المادة';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: TextFormField(
                          controller: _amountController,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.format_list_numbered),
                            hintText: 'الكمية',
                            border: InputBorder.none,
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال الكمية';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: TextFormField(
                          controller: _leftAmountController,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.format_list_numbered),
                            hintText: 'الكمية المتبقية',
                            border: InputBorder.none,
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال الكمية المتبقية';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: TextFormField(
                          controller: _productAmountController,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.production_quantity_limits),
                            hintText: 'كمية المنتجات المصنعة',
                            border: InputBorder.none,
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كمية المنتجات المصنعة';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    ElevatedButton(
                      onPressed: _calculateDeadMaterials,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7),
                      ),
                      child: const Text('احسب كمية الهالك والنسبة', style: TextStyle(
                          color: Colors.white
                      ),),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.orange.withOpacity(0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}