import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DecreaseInjectedProductPage extends StatefulWidget {
  const DecreaseInjectedProductPage({super.key});

  @override
  _DecreaseInjectedProductPageState createState() => _DecreaseInjectedProductPageState();
}

class _DecreaseInjectedProductPageState extends State<DecreaseInjectedProductPage> {
  final List<String> _products = [];
  String? _selectedProduct;
  DateTime? _selectedDate;
  final List<Map<String, dynamic>> _addedProducts = [];
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int? _editingIndex;
  bool _dataSaved = false;
  bool _dataModified = false;
  bool _isSaving = false;
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('data').doc('lists').get();
      if (doc.exists) {
        setState(() {
          _products.addAll(List<String>.from(doc['products']));
          _isFetching = false;
        });
      }
    } catch (e) {
      print('Error fetching products: $e');
      setState(() {
        _isFetching = false;
      });
    }
  }

  void _pickDate() async {
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
        _selectedDate = picked;
        _dateController.text = "${picked.toLocal()}".split(' ')[0];
        _dataModified = true;
      });
    }
  }

  void _addProduct() {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار التاريخ')),
        );
        return;
      }
      setState(() {
        bool productExists = false;
        for (var product in _addedProducts) {
          if (product['product'] == _selectedProduct) {
            product['amount'] = (int.parse(product['amount']) + int.parse(_amountController.text)).toString();
            productExists = true;
            break;
          }
        }
        if (!productExists) {
          _addedProducts.add({
            'product': _selectedProduct,
            'date': _selectedDate,
            'amount': _amountController.text,
          });
        }
        _selectedProduct = null;
        _amountController.clear();
        _dataModified = true;
      });
    }
  }

  void _editProduct(int index) {
    setState(() {
      _selectedProduct = _addedProducts[index]['product'];
      _selectedDate = _addedProducts[index]['date'];
      _amountController.text = _addedProducts[index]['amount'];
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
      _editingIndex = index;
    });
  }

  void _deleteProduct(int index) {
    setState(() {
      _addedProducts.removeAt(index);
      _dataModified = true;
    });
  }

  void _saveData() async {
    if (!_dataModified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data already saved')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    for (var product in _addedProducts) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('injectedProducts')
          .where('product', isEqualTo: product['product'])
          .get();

      if (query.docs.isNotEmpty) {
        for (var doc in query.docs) {
          int existingAmount = int.parse(doc['amount']);
          int newAmount = existingAmount - int.parse(product['amount']);
          await FirebaseFirestore.instance
              .collection('injectedProducts')
              .doc(doc.id)
              .update({
            'amount': newAmount.toString(),
          });

          await FirebaseFirestore.instance
              .collection('injectedProducts')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': product['date'],
            'amount': product['amount'],
            'type': 'decrease',
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not found')),
        );
      }
    }

    setState(() {
      _dataSaved = true;
      _dataModified = false;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحفظ بنجاح')),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 18.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('صرف منتج', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
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
                    Center(
                      child: Card(
                        margin: EdgeInsets.symmetric(horizontal: 5.w, vertical: 8.h),
                        elevation: 2,
                        color: Colors.orange.withOpacity(0.8),
                        child: IconButton(
                          icon: Icon(Icons.calendar_month, color: Colors.black.withOpacity(0.7)),
                          onPressed: _pickDate,
                        ),
                      ),
                    ),
                    Stack(
                      children: [
                        Card(
                          margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.shopping_cart),
                                hintText: 'اختر المنتج',
                                border: InputBorder.none,
                              ),
                              value: _selectedProduct,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedProduct = newValue;
                                  _dataModified = true;
                                });
                              },
                              items: _products.map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'يرجى اختيار المنتج';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        if (_isFetching)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
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
                            hintText: 'أدخل الكمية',
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
                          onChanged: (value) {
                            _dataModified = true;
                          },
                        ),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        onPressed: _addProduct,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7),
                        ),
                        child: Text(
                          _editingIndex != null ? 'تحديث المنتج' : 'إضافة منتج',
                          style: TextStyle(
                            fontSize: 18.sp,
                            color: Colors.white.withOpacity(1),
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('التاريخ', style: headTableTextStyle)),
                          DataColumn(label: Text('المنتج', style: headTableTextStyle)),
                          DataColumn(label: Text('الكمية', style: headTableTextStyle)),
                          DataColumn(label: Text('تعديل وحذف', style: headTableTextStyle)),
                        ],
                        rows: _addedProducts.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> product = entry.value;
                          return DataRow(cells: [
                            DataCell(Text(product['date'].toString().split(' ')[0], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(product['product'], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(product['amount'], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.black.withOpacity(0.7)),
                                  onPressed: () => _editProduct(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.black.withOpacity(0.7)),
                                  onPressed: () => _deleteProduct(index),
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        onPressed: _saveData,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7),
                        ),
                        child: Text(
                          'حفظ',
                          style: TextStyle(
                            fontSize: 20.sp,
                            color: Colors.white.withOpacity(1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isSaving)
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