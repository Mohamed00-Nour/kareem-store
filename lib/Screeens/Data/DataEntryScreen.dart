import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:math';

class DataEntryScreen extends StatefulWidget {
  const DataEntryScreen({super.key});

  @override
  _DataEntryScreenState createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _sellingPrice1Controller = TextEditingController();
  final TextEditingController _sellingPrice2Controller = TextEditingController();
  final TextEditingController _sellingPrice3Controller = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _alertAmountController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();

  final List<Product> _products = [];
  final List<String> _suppliers = [];
  List<String> _departments = [];
  String? _selectedDepartment;
  bool _onDemand = false;
  bool _retail = false;

  bool _isLoading = false;
  bool _isAddingProduct = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('departments').get();
      setState(() {
        _departments = querySnapshot.docs
            .map((doc) => doc['name'] as String)
            .toList();
      });
    } catch (e) {
      print('Error loading departments: $e');
    }
  }

Future<void> _addDepartment() async {
  if (_departmentController.text.isNotEmpty) {
    String newDepartment = _departmentController.text.trim();

    try {
      // Check if the department already exists
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('departments')
          .where('name', isEqualTo: newDepartment)
          .get();

      if (query.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('القسم موجود بالفعل')),
        );
        return;
      }

      // Add the new department if it doesn't exist
      await FirebaseFirestore.instance
          .collection('departments')
          .add({'name': newDepartment});

      setState(() {
        _departments.add(newDepartment);
        _departmentController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة القسم بنجاح')),
      );
    } catch (e) {
      print('Error adding department: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء إضافة القسم: $e')),
      );
    }
  }
}
double _optionalDouble(TextEditingController controller) {
  final text = controller.text.trim();
  if (text.isEmpty) return 0.0;
  return double.tryParse(text) ?? 0.0;
}

Future<bool> _productExistsInDatabase(String productName) async {
  final query = await FirebaseFirestore.instance
      .collection('products')
      .where('name', isEqualTo: productName)
      .limit(1)
      .get();
  return query.docs.isNotEmpty;
}

Future<void> _addProduct() async {
  if (!_formKey.currentState!.validate()) return;

  final productName = _productNameController.text
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  if (_products.any((product) => product.name == productName)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('المنتج موجود بالفعل في القائمة')),
    );
    return;
  }

  setState(() => _isAddingProduct = true);
  try {
    if (await _productExistsInDatabase(productName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('المنتج موجود بالفعل في قاعدة البيانات')),
      );
      return;
    }

    final random = Random();
    // Firestore document IDs cannot contain "/"; use auto id, store name as field.
    final docId =
        FirebaseFirestore.instance.collection('products').doc().id;
    final newProduct = Product(
      id: docId,
      randomNumber: random.nextInt(1000000),
      name: productName,
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      department: _selectedDepartment ?? '',
      sellingPrice1: _optionalDouble(_sellingPrice1Controller),
      sellingPrice2: _optionalDouble(_sellingPrice2Controller),
      sellingPrice3: _optionalDouble(_sellingPrice3Controller),
      costPrice: _optionalDouble(_costPriceController),
      quantity: _optionalDouble(_quantityController),
      alertAmount: _optionalDouble(_alertAmountController),
      onDemand: _onDemand,
      retail: _retail,
      image: _selectedImage?.path,
    );

    if (!mounted) return;
    setState(() {
      _products.add(newProduct);
      _productNameController.clear();
      _descriptionController.clear();
      _sellingPrice1Controller.clear();
      _sellingPrice2Controller.clear();
      _sellingPrice3Controller.clear();
      _costPriceController.clear();
      _quantityController.clear();
      _alertAmountController.clear();
      _imageController.clear();
      _selectedImage = null;
      _selectedDepartment = null;
      _onDemand = false;
      _retail = false;
    });
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ أثناء التحقق من المنتج: $e')),
    );
  } finally {
    if (mounted) setState(() => _isAddingProduct = false);
  }
}

Future<void> _saveData() async {
  if (_isLoading) return;
  if (_products.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لا توجد منتجات للحفظ')),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final productsRef =
        FirebaseFirestore.instance.collection('products');
    var savedCount = 0;
    var skippedCount = 0;

    for (final product in _products) {
      if (await _productExistsInDatabase(product.name)) {
        skippedCount++;
        continue;
      }
      if (product.image != null) {
        product.image = await _uploadImage(File(product.image!));
      }
      await productsRef.doc(product.id).set(product.toMap());
      savedCount++;
    }

    if (!mounted) return;
    if (savedCount > 0) {
      setState(() => _products.clear());
    }
    final message = skippedCount > 0
        ? 'تم حفظ $savedCount منتج، وتخطي $skippedCount موجود مسبقاً'
        : 'تم حفظ البيانات بنجاح';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}


  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image selected')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }


  Future<String> _uploadImage(File imageFile) async {
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final imagesRef = storageRef.child('images/${imageFile.path.split('/').last}');
      final uploadTask = imagesRef.putFile(imageFile);
      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print(e);
      return '';
    }
  }

  Widget _buildDepartmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('القسم (اختياري)',
            style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black.withOpacity(0.7))),
        Row(
          children: [
            Expanded(
              child: Card(
                margin: EdgeInsets.symmetric(vertical: 8.h),
                elevation: 2,
                color: Colors.orange.withOpacity(0.8),
                child: Padding(
                  padding: EdgeInsets.all(5.w),
                  child: DropdownButtonFormField<String>(
                    value: _selectedDepartment,
                    items: _departments.map((department) {
                      return DropdownMenuItem(
                        value: department,
                        child: Text(department),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedDepartment = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'اختر القسم (اختياري)',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, color: Colors.black.withOpacity(0.7)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text('إضافة قسم جديد'),
                      content: TextField(
                        controller: _departmentController,
                        decoration: InputDecoration(hintText: 'اسم القسم'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text('إلغاء'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _addDepartment();
                            Navigator.of(context).pop();
                          },
                          child: Text('إضافة'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إدخال البيانات',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0.w),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildProductInputSection(),
                  SizedBox(height: 15.h),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveData,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0.r),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                      disabledBackgroundColor: Colors.grey.shade500,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22.w,
                            height: 22.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'حفظ البيانات',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: Colors.white.withOpacity(1),
                            ),
                          ),
                  ),
                ],
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

  Widget _buildProductInputSection() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المنتجات',
              style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.7))),
          _buildTextField('اسم المنتج', _productNameController, required: true),
          _buildTextField('الوصف (اختياري)', _descriptionController),
          Row(
            children: [
              Expanded(
                  child: _buildTextField('سعر البيع 1', _sellingPrice1Controller,
                      isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _buildTextField('سعر البيع 2', _sellingPrice2Controller,
                      isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _buildTextField('سعر البيع 3', _sellingPrice3Controller,
                      isNumber: true)),
            ],
          ),
          _buildTextField('سعر التكلفة', _costPriceController, isNumber: true),
          Row(
            children: [
              Expanded(
                  child: _buildTextField('الكمية', _quantityController,
                      isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(
                  child: _buildTextField(
                      'الكمية التنبيهية', _alertAmountController,
                      isNumber: true)),
            ],
          ),
          _buildDepartmentDropdown(),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'حسب الطلب',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  value: _onDemand,
                  activeColor: Colors.black.withOpacity(0.7),
                  onChanged: (value) {
                    setState(() {
                      _onDemand = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'قطاعي',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  value: _retail,
                  activeColor: Colors.black.withOpacity(0.7),
                  onChanged: (value) {
                    setState(() {
                      _retail = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ],
          ),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.gallery),
                child: Text('اختر صورة من المعرض'),
              ),
              SizedBox(width: 8.w),
              ElevatedButton(
                onPressed: () => _pickImage(ImageSource.camera),
                child: Text('التقط صورة'),
              ),
            ],
          ),
          if (_selectedImage != null)
            Image.file(_selectedImage!, height: 100.h, width: 100.w),
          Center(
            child: ElevatedButton(
              onPressed: _isAddingProduct || _isLoading ? null : _addProduct,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0.r),
                ),
                backgroundColor: Colors.black.withOpacity(0.7),
                disabledBackgroundColor: Colors.grey.shade500,
              ),
              child: _isAddingProduct
                  ? SizedBox(
                      width: 22.w,
                      height: 22.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'إضافة المنتج',
                      style: TextStyle(
                        fontSize: 18.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
            ),
          ),
          Wrap(
            children: _products.map((product) {
              return Chip(
                label: Text(product.name),
                deleteIcon: Icon(Icons.close, size: 15),
                onDeleted: () {
                  setState(() {
                    _products.remove(product);
                  });
                },
              );
            }).toList(),
          ),
          SizedBox(height: 10.h),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    TextEditingController controller, {
    bool isNumber = false,
    bool required = false,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.all(5.w),
        child: TextFormField(
          controller: controller,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            border: InputBorder.none,
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) {
              return 'هذا الحقل مطلوب';
            }
            if (isNumber && text.isNotEmpty && double.tryParse(text) == null) {
              return 'يرجى إدخال رقم صالح';
            }
            if (hint.startsWith('سعر بيع') && text.isNotEmpty) {
              final sell = double.tryParse(text);
              final costText = _costPriceController.text.trim();
              if (sell != null &&
                  costText.isNotEmpty &&
                  double.tryParse(costText) != null &&
                  sell <= double.parse(costText)) {
                return 'يجب أن يكون سعر البيع أكبر من سعر التكلفة';
              }
            }
            return null;
          },
        ),
      ),
    );
  }
}

class Product {
  String id;
  int randomNumber;
  String name;
  String? description;
  String department;
  double sellingPrice1;
  double sellingPrice2;
  double sellingPrice3;
  double costPrice;
  double quantity;
  double alertAmount;
  bool onDemand;
  bool retail;
  String? image;

  Product({
    required this.id,
    required this.randomNumber,
    required this.name,
    this.description,
    required this.department,
    required this.sellingPrice1,
    required this.sellingPrice2,
    required this.sellingPrice3,
    required this.costPrice,
    required this.quantity,
    required this.alertAmount,
    this.onDemand = false,
    this.retail = false,
    this.image,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'randomNumber': randomNumber,
      'name': name,
      'description': description,
      'department': department,
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'costPrice': costPrice,
      'quantity': quantity,
      'alertAmount': alertAmount,
      'onDemand': onDemand,
      'retail': retail,
      'image': image,
    };
  }
}