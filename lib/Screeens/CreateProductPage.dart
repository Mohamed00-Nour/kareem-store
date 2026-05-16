import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CreateProductPage extends StatefulWidget {
  const CreateProductPage({super.key});

  @override
  _CreateProductPageState createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sellingPrice1Controller = TextEditingController();
  final TextEditingController _sellingPrice2Controller = TextEditingController();
  final TextEditingController _sellingPrice3Controller = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(text: '0');
  final TextEditingController _alertAmountController = TextEditingController(text: '0');
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _randomNumberController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();

  List<String> _departments = [];
  String? _selectedDepartment;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('departments')
          .get();
      setState(() {
        _departments =
            snapshot.docs.map((d) => d['name'] as String).toSet().toList();
      });
    } catch (_) {}
  }

  Future<void> _addDepartment() async {
    if (_departmentController.text.isNotEmpty) {
      final name = _departmentController.text.trim();
      await FirebaseFirestore.instance
          .collection('departments')
          .add({'name': name});
      setState(() {
        _departments.add(name);
        _selectedDepartment = name;
        _departmentController.clear();
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Get next random number
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .orderBy('randomNumber', descending: true)
          .limit(1)
          .get();
      int nextRandom = 1;
      if (snap.docs.isNotEmpty) {
        nextRandom = ((snap.docs.first['randomNumber'] ?? 0) as num).toInt() + 1;
      }
      if (_randomNumberController.text.isNotEmpty) {
        nextRandom = int.tryParse(_randomNumberController.text) ?? nextRandom;
      }

      final ref = await FirebaseFirestore.instance.collection('products').add({
        'name': _nameController.text.trim(),
        'sellingPrice1': double.tryParse(_sellingPrice1Controller.text) ?? 0.0,
        'sellingPrice2': double.tryParse(_sellingPrice2Controller.text) ?? 0.0,
        'sellingPrice3': double.tryParse(_sellingPrice3Controller.text) ?? 0.0,
        'costPrice': double.tryParse(_costPriceController.text) ?? 0.0,
        'quantity': double.tryParse(_quantityController.text) ?? 0.0,
        'alertAmount': double.tryParse(_alertAmountController.text) ?? 0.0,
        'image': _imageController.text.isNotEmpty ? _imageController.text : null,
        'randomNumber': nextRandom,
        'department': _selectedDepartment,
      });
      await ref.update({'id': ref.id});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إضافة المنتج بنجاح')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCard(
    String label,
    TextEditingController controller,
    TextInputType keyboardType, {
    bool isOptional = false,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.all(8.w),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
          ),
          validator: (v) {
            if (!isOptional && (v == null || v.isEmpty)) {
              return 'يرجى إدخال $label';
            }
            return null;
          },
        ),
      ),
    );
  }

  Widget _buildDepartmentDropdown() {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.all(8.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedDepartment,
              items: _departments
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDepartment = v),
              decoration: const InputDecoration(
                  hintText: 'اختر القسم', border: InputBorder.none),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.add,
                    color: Colors.black.withOpacity(0.7)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('إضافة قسم جديد'),
                      content: TextField(
                        controller: _departmentController,
                        decoration:
                            const InputDecoration(hintText: 'اسم القسم'),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إلغاء')),
                        TextButton(
                            onPressed: () async {
                              await _addDepartment();
                              if (mounted) Navigator.pop(context);
                            },
                            child: const Text('إضافة')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('إضافة منتج جديد',
              style: TextStyle(fontSize: 20.sp, color: Colors.white)),
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            children: [
              _buildCard('اسم المنتج', _nameController, TextInputType.text),
              Row(children: [
                Expanded(
                    child: _buildCard(
                        'سعر بيع 1', _sellingPrice1Controller,
                        TextInputType.number)),
                Expanded(
                    child: _buildCard(
                        'سعر بيع 2', _sellingPrice2Controller,
                        TextInputType.number)),
                Expanded(
                    child: _buildCard(
                        'سعر بيع 3', _sellingPrice3Controller,
                        TextInputType.number)),
              ]),
              _buildCard('سعر التكلفة', _costPriceController,
                  TextInputType.number),
              Row(children: [
                Expanded(
                    child: _buildCard('الكمية الحالية', _quantityController,
                        TextInputType.number)),
                Expanded(
                    child: _buildCard('الكمية التنبيهية',
                        _alertAmountController, TextInputType.number)),
              ]),
              _buildCard('الرقم التسلسلي (اختياري)',
                  _randomNumberController, TextInputType.number,
                  isOptional: true),
              _buildCard('رابط الصورة (اختياري)', _imageController,
                  TextInputType.url,
                  isOptional: true),
              _buildDepartmentDropdown(),
              SizedBox(height: 20.h),
              Center(
                child: _isSaving
                    ? CircularProgressIndicator(
                        color: Colors.orange.withOpacity(0.8))
                    : ElevatedButton(
                        onPressed: _saveProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.black.withOpacity(0.7),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r)),
                          padding: EdgeInsets.symmetric(
                              horizontal: 40.w, vertical: 12.h),
                        ),
                        child: Text('حفظ المنتج',
                            style: TextStyle(
                                fontSize: 16.sp, color: Colors.white)),
                      ),
              ),
              SizedBox(height: 30.h),
            ],
          ),
        ),
      ),
    );
  }
}
