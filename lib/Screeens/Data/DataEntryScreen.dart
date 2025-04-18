import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

class DataEntryScreen extends StatefulWidget {
  const DataEntryScreen({super.key});

  @override
  _DataEntryScreenState createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _productNameController = TextEditingController();
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

  bool _isLoading = false;
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
      String newDepartment = _departmentController.text;
      try {
        await FirebaseFirestore.instance
            .collection('departments')
            .add({'name': newDepartment});
        setState(() {
          _departments.add(newDepartment);
          _departmentController.clear();
        });
      } catch (e) {
        print('Error adding department: $e');
      }
    }
  }

  void _addProduct() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDepartment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار قسم')),
        );
        return;
      }

      double costPrice = double.parse(_costPriceController.text);
      double sellingPrice1 = double.parse(_sellingPrice1Controller.text);
      double sellingPrice2 = double.parse(_sellingPrice2Controller.text);
      double sellingPrice3 = double.parse(_sellingPrice3Controller.text);

      if (sellingPrice1 <= costPrice || sellingPrice2 <= costPrice || sellingPrice3 <= costPrice) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب أن يكون سعر البيع أكبر من سعر التكلفة')),
        );
        return;
      }

      if (sellingPrice1 == sellingPrice2 || sellingPrice1 == sellingPrice3 || sellingPrice2 == sellingPrice3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب أن تكون أسعار البيع مختلفة')),
        );
        return;
      }

      String productName = _productNameController.text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

      // Check if the product already exists
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: productName)
          .get();

      if (query.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المنتج موجود بالفعل')),
        );
        return;
      }

      var uuid = Uuid();
      var random = Random();
      Product newProduct = Product(
        id: uuid.v4(),
        randomNumber: random.nextInt(1000000),
        name: productName,
        department: _selectedDepartment!,
        sellingPrice1: sellingPrice1,
        sellingPrice2: sellingPrice2,
        sellingPrice3: sellingPrice3,
        costPrice: costPrice,
        quantity: int.parse(_quantityController.text),
        alertAmount: int.parse(_alertAmountController.text),
        image: _selectedImage?.path,
      );

      try {
        if (newProduct.image != null) {
          newProduct.image = await _uploadImage(File(newProduct.image!));
        }
        // Save the product with the product name as the document ID
        await FirebaseFirestore.instance
            .collection('products')
            .doc(productName)
            .set(newProduct.toMap());
        setState(() {
          _products.add(newProduct);
          _productNameController.clear();
          _sellingPrice1Controller.clear();
          _sellingPrice2Controller.clear();
          _sellingPrice3Controller.clear();
          _costPriceController.clear();
          _quantityController.clear();
          _alertAmountController.clear();
          _imageController.clear();
          _selectedImage = null;
          _selectedDepartment = null;
        });
      } catch (e) {
        print('Error adding product: $e');
      }
    }
  }

  Future<void> _saveData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Save products
      if (_products.isNotEmpty) {
        CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
        for (var product in _products) {
          if (product.image != null) {
            product.image = await _uploadImage(File(product.image!));
          }
          await productsRef.doc(product.id).set(product.toMap());
        }
      }

      // Save suppliers
      if (_suppliers.isNotEmpty) {
        CollectionReference suppliersRef = FirebaseFirestore.instance.collection('suppliers');
        for (var supplier in _suppliers) {
          await suppliersRef.add({'name': supplier});
        }
      }

      // Save departments
      if (_departments.isNotEmpty) {
        CollectionReference departmentsRef = FirebaseFirestore.instance.collection('departments');
        for (var department in _departments) {
          QuerySnapshot query = await departmentsRef.where('name', isEqualTo: department).get();
          if (query.docs.isEmpty) {
            await departmentsRef.add({'name': department});
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving data: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
        Text('القسم',
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
                      hintText: 'اختر القسم',
                      border: InputBorder.none,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى اختيار قسم';
                      }
                      return null;
                    },
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
    ScreenUtil.init(context,
        designSize: const Size(360, 690),
        minTextAdapt: true,
        splitScreenMode: true);

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
                    onPressed: _saveData,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0.r),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
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
          _buildTextField('اسم المنتج', _productNameController),
          Row(
            children: [
              Expanded(child: _buildTextField('سعر البيع 1', _sellingPrice1Controller, isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(child: _buildTextField('سعر البيع 2', _sellingPrice2Controller, isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(child: _buildTextField('سعر البيع 3', _sellingPrice3Controller, isNumber: true)),
            ],
          ),
          _buildTextField('سعر التكلفة', _costPriceController, isNumber: true),
          Row(
            children: [
              Expanded(child: _buildTextField('الكمية', _quantityController, isNumber: true)),
              SizedBox(width: 8.w),
              Expanded(child: _buildTextField('الكمية التنبيهية', _alertAmountController, isNumber: true)),
            ],
          ),
          _buildDepartmentDropdown(),
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
              onPressed: _addProduct,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0.r),
                ),
                backgroundColor: Colors.black.withOpacity(0.7),
              ),
              child: Text(
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

  Widget _buildTextField(String hint, TextEditingController controller, {bool isNumber = false}) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.all(5.w),
        child: TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            border: InputBorder.none,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'هذا الحقل مطلوب';
            }
            if (isNumber && double.tryParse(value) == null) {
              return 'يرجى إدخال رقم صالح';
            }
            if (hint.startsWith('سعر بيع') && double.tryParse(value)! <= double.tryParse(_costPriceController.text)!) {
              return 'يجب أن يكون سعر البيع أكبر من سعر التكلفة';
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
  String department;
  double sellingPrice1;
  double sellingPrice2;
  double sellingPrice3;
  double costPrice;
  int quantity;
  int alertAmount;
  String? image;

  Product({
    required this.id,
    required this.randomNumber,
    required this.name,
    required this.department,
    required this.sellingPrice1,
    required this.sellingPrice2,
    required this.sellingPrice3,
    required this.costPrice,
    required this.quantity,
    required this.alertAmount,
    this.image,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'randomNumber': randomNumber,
      'name': name,
      'department': department,
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'costPrice': costPrice,
      'quantity': quantity,
      'alertAmount': alertAmount,
      'image': image,
    };
  }
}