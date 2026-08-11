import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'sync/connectivity_service.dart';
import 'sync/sync_queue_manager.dart';
import 'repositories/product_repository.dart';
import 'Services/invoice_number_utils.dart';

class EditProductPage extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> productData;

  const EditProductPage(
      {required this.productId, required this.productData, super.key});

  @override
  _EditProductPageState createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _sellingPrice1Controller;
  late TextEditingController _sellingPrice2Controller;
  late TextEditingController _sellingPrice3Controller;
  late TextEditingController _costPriceController;
  late TextEditingController _quantityController;
  late TextEditingController _alertAmountController;
  late TextEditingController _imageController;
  late TextEditingController _randomNumberController;
  late TextEditingController _departmentController;

  List<String> _departments = [];
  String? _selectedDepartment;
  bool _onDemand = false;
  bool _retail = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.productData['name']);
    _descriptionController =
        TextEditingController(text: widget.productData['description'] ?? '');
    _sellingPrice1Controller = TextEditingController(
        text: widget.productData['sellingPrice1'].toString());
    _sellingPrice2Controller = TextEditingController(
        text: widget.productData['sellingPrice2'].toString());
    _sellingPrice3Controller = TextEditingController(
        text: widget.productData['sellingPrice3'].toString());
    _costPriceController =
        TextEditingController(text: widget.productData['costPrice'].toString());
    _quantityController =
        TextEditingController(text: widget.productData['quantity'].toString());
    _alertAmountController = TextEditingController(
        text: widget.productData['alertAmount'].toString());
    _imageController =
        TextEditingController(text: widget.productData['image'] ?? '');
    _randomNumberController = TextEditingController(
        text: widget.productData['randomNumber'].toString());
    _departmentController = TextEditingController();
    _selectedDepartment = widget.productData['department'];
    _onDemand = widget.productData['onDemand'] == true;
    _retail = widget.productData['retail'] == true;
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sellingPrice1Controller.dispose();
    _sellingPrice2Controller.dispose();
    _sellingPrice3Controller.dispose();
    _costPriceController.dispose();
    _quantityController.dispose();
    _alertAmountController.dispose();
    _imageController.dispose();
    _randomNumberController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      if (!ConnectivityService.instance.isOnline) return;
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('departments').get();
      setState(() {
        _departments = querySnapshot.docs
            .map((doc) => doc['name'] as String)
            .toSet()
            .toList();
        if (!_departments.contains(_selectedDepartment)) {
          _selectedDepartment = null;
        }
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
          _selectedDepartment = newDepartment;
          _departmentController.clear();
        });
      } catch (e) {
        print('Error adding department: $e');
      }
    }
  }

  Future<void> _saveProduct() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'sellingPrice1': double.parse(_sellingPrice1Controller.text),
        'sellingPrice2': double.parse(_sellingPrice2Controller.text),
        'sellingPrice3': double.parse(_sellingPrice3Controller.text),
        'costPrice': double.parse(_costPriceController.text),
        'quantity': double.parse(_quantityController.text),
        'alertAmount': double.parse(_alertAmountController.text),
        'image':
            _imageController.text.isNotEmpty ? _imageController.text : null,
        'randomNumber': int.parse(_randomNumberController.text),
        'department': _selectedDepartment,
        'onDemand': _onDemand,
        'retail': _retail,
      };

      if (ConnectivityService.instance.isOnline) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .update(updateData);
      } else {
        await SyncQueueManager.instance.enqueue(
          operationType: 'editProduct',
          payload: {
            'productId': widget.productId,
            'data': updateData,
          },
        );
      }

      // Update local Hive cache immediately
      await ProductRepository.instance.upsertLocal(widget.productId, {
        ...widget.productData,
        ...updateData,
        'id': widget.productId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ البيانات بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _navigateToProductChanges() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductChangesPage(productId: widget.productId),
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
              decoration: const InputDecoration(
                hintText: 'اختر القسم (اختياري)',
                border: InputBorder.none,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductOptionsCard() {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        child: Row(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تعديل المنتج',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 0.w, vertical: 5.h),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  _buildCard('اسم المنتج', _nameController, TextInputType.text),
                  _buildCard(
                      'الوصف', _descriptionController, TextInputType.text,
                      isOptional: true),
                  Row(
                    children: [
                      Expanded(
                          child: _buildCard('سعر بيع 1',
                              _sellingPrice1Controller, TextInputType.number)),
                      Expanded(
                          child: _buildCard('سعر بيع 2',
                              _sellingPrice2Controller, TextInputType.number)),
                      Expanded(
                          child: _buildCard('سعر ببع 3',
                              _sellingPrice3Controller, TextInputType.number)),
                    ],
                  ),
                  _buildCard('سعر التكلفة', _costPriceController,
                      TextInputType.number),
                  Row(
                    children: [
                      Expanded(
                          child: _buildCard('الكمية الحالية',
                              _quantityController, TextInputType.number)),
                      Expanded(
                          child: _buildCard('الكمية التنبيهية',
                              _alertAmountController, TextInputType.number)),
                    ],
                  ),
                  _buildCard('الصورة', _imageController, TextInputType.text,
                      isOptional: true),
                  _buildDepartmentDropdown(),
                  _buildProductOptionsCard(),
                  SizedBox(height: 20.h),
                  Center(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'حفظ',
                              style: TextStyle(
                                  fontSize: 16.sp, color: Colors.white),
                            ),
                    ),
                  ),
                  Center(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _navigateToProductChanges,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7),
                      ),
                      child: Text(
                        'عرض التغييرات',
                        style: TextStyle(fontSize: 16.sp, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black.withOpacity(0.45),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12.h),
                    Text(
                      'جاري الحفظ...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(String label, TextEditingController controller,
      TextInputType keyboardType,
      {bool isOptional = false}) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      color: Colors.orange.withOpacity(0.8),
      child: Padding(
        padding: EdgeInsets.all(8.w),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
          ),
          keyboardType: keyboardType,
          validator: (value) {
            if (!isOptional && (value == null || value.isEmpty)) {
              return 'Please enter $label';
            }
            return null;
          },
        ),
      ),
    );
  }
}

class ProductChangesPage extends StatelessWidget {
  final String productId;

  const ProductChangesPage({required this.productId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تغييرات المنتج',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .collection('changes')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final changes = snapshot.data!.docs;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(
                    label: Text('التاريخ',
                        style: TextStyle(
                            fontSize: 18.sp, fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الكمية',
                        style: TextStyle(
                            fontSize: 18.sp, fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('النوع',
                        style: TextStyle(
                            fontSize: 18.sp, fontWeight: FontWeight.bold))),
              ],
              rows: changes.map((change) {
                return DataRow(cells: [
                  DataCell(Text(
                      (change['date'] as Timestamp)
                          .toDate()
                          .toString()
                          .split(' ')[0],
                      style: TextStyle(fontSize: 14.sp))),
                  DataCell(Text(invoiceAmount(change['amount']),
                      style: TextStyle(fontSize: 14.sp))),
                  DataCell(Text(
                    change['type'] == 'decrease'
                        ? 'بيع'
                        : change['type'] == 'update'
                            ? 'تحديث'
                            : 'شراء',
                    style: TextStyle(fontSize: 14.sp),
                  )),
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
