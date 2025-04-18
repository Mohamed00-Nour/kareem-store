import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  _AddProductPageState createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final List<Product> _products = [];
  Product? _selectedProduct;
  Supplier? _selectedSupplier;
  DateTime? _selectedDate;
  final List<Map<String, dynamic>> _addedProducts = [];
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  TextEditingController _supplierController = TextEditingController();
  TextEditingController _productController = TextEditingController();
  final TextEditingController _supplierNameController = TextEditingController();
  final TextEditingController _newSupplierNameController =
      TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  List<Supplier> _suppliers = [];
  double _totalCost = 0.0;
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
    _fetchSuppliers();
    _selectedDate = DateTime.now();
    _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
  }

  @override
  void dispose() {
    _supplierNameController.dispose();
    _newSupplierNameController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('products').get();
      setState(() {
        _products.addAll(querySnapshot.docs
            .map((doc) => Product.fromMap(doc.data() as Map<String, dynamic>)));
        _isFetching = false;
      });
    } catch (e) {
      print('Error fetching products: $e');
      setState(() {
        _isFetching = false;
      });
    }
  }

  Future<void> _fetchSuppliers() async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('suppliers').get();
      setState(() {
        _suppliers = querySnapshot.docs
            .map((doc) => Supplier.fromMap(doc.data() as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      print('Error fetching suppliers: $e');
    }
  }

  void _showSupplierDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('أدخل اسم المورد والمبلغ المدفوع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Supplier>(
                decoration: const InputDecoration(hintText: 'اختر اسم المورد'),
                items: _suppliers.map((Supplier supplier) {
                  return DropdownMenuItem<Supplier>(
                    value: supplier,
                    child: Text(supplier.name),
                  );
                }).toList()
                  ..add(
                    DropdownMenuItem<Supplier>(
                      value:
                          Supplier(id: 'new_supplier', name: 'إضافة مورد جديد'),
                      child: Text('إضافة مورد جديد'),
                    ),
                  ),
                onChanged: (Supplier? newValue) {
                  setState(() {
                    if (newValue?.id == 'new_supplier') {
                      _supplierNameController.clear();
                      _selectedSupplier = null;
                    } else {
                      _supplierNameController.text = newValue!.name;
                      _selectedSupplier = newValue;
                    }
                  });
                },
                value: _selectedSupplier,
              ),
              if (_selectedSupplier == null)
                TextField(
                  controller: _supplierNameController,
                  decoration:
                      const InputDecoration(hintText: 'اسم المورد الجديد'),
                ),
              TextField(
                controller: _paidAmountController,
                decoration: const InputDecoration(hintText: 'المبلغ المدفوع'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('حفظ'),
              onPressed: () {
                setState(() {
                  if (_selectedSupplier == null &&
                      _supplierNameController.text.isNotEmpty) {
                    Supplier newSupplier =
                        Supplier(id: '', name: _supplierNameController.text);
                    _suppliers.add(newSupplier);
                    _selectedSupplier = newSupplier;
                  }
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  double _calculateTotalSum() {
    double totalSum = 0.0;
    for (var product in _addedProducts) {
      totalSum += double.parse(product['totalCost']);
    }
    return totalSum;
  }

  void _pickDate() async {
    final int currentYear = DateTime.now().year;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(currentYear, 1, 1),
      lastDate: DateTime(currentYear, 12, 31),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.orange.withOpacity(0.7),
            hintColor: Colors.orange.withOpacity(0.7),
            colorScheme: const ColorScheme.light(primary: Colors.orange),
            buttonTheme:
                const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Colors.black),
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

  void _calculateTotalCost() {
    setState(() {
      _totalCost = (double.tryParse(_costController.text) ?? 0.0) *
                   (double.tryParse(_amountController.text) ?? 0.0);
      _totalCost = double.parse(_totalCost.toStringAsFixed(2)); // Format total cost
    });
  }

void _addProduct() async {
  if (_formKey.currentState!.validate()) {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار التاريخ')),
      );
      return;
    }

    bool productExists = false;

    // Update the product quantities and save changes
    for (var product in _addedProducts) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product['product'])
          .get();

      if (query.docs.isNotEmpty) {
        for (var doc in query.docs) {
          int existingAmount = doc['quantity'];
          int newAmount = existingAmount + int.parse(product['amount']);
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .update({
            'quantity': newAmount,
          });

          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': product['date'],
            'amount': int.parse(product['amount']), // Ensure amount is an integer
            'type': 'increase',
          });
        }
      }
    }

    setState(() {
      if (!productExists) {
        _addedProducts.add({
          'product': _selectedProduct!.name,
          'date': _selectedDate,
          'amount': _amountController.text,
          'cost': _costController.text,
          'totalCost': _totalCost.toString(),
        });
      }
      _selectedProduct = null;
      _selectedSupplier = null;
      _amountController.clear();
      _costController.clear();
      _supplierController.clear();
      _productController.clear();
      _totalCost = 0.0;
      _dataModified = true;
    });
  }
}
  void _editProduct(int index) {
    setState(() {
      _selectedProduct = _products.firstWhere(
          (product) => product.name == _addedProducts[index]['product'],
          orElse: () => Product(
              id: '',
              randomNumber: 0,
              name: '',
              sellingPrice1: 0,
              sellingPrice2: 0,
              sellingPrice3: 0,
              costPrice: 0,
              quantity: 0,
              alertAmount: 0));
      _selectedSupplier = _suppliers.firstWhere(
          (supplier) => supplier.name == _addedProducts[index]['supplier'],
          orElse: () => Supplier(id: '', name: ''));
      _selectedDate = _addedProducts[index]['date'];
      _amountController.text = _addedProducts[index]['amount'];
      _costController.text = _addedProducts[index]['cost'];
      _totalCost = double.parse(_addedProducts[index]['totalCost']);
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
      _productController.text =
          _selectedProduct!.name; // Restore the product name field
      _supplierController.text =
          _selectedSupplier?.name ?? ''; // Restore the supplier name field
      _editingIndex = index;
      _addedProducts.removeAt(index); // Remove the previous record
    });
  }

  void _deleteProduct(int index) {
    setState(() {
      _addedProducts.removeAt(index);
      _selectedProduct = null;
      _selectedSupplier = null;
      _selectedDate = DateTime.now();
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
      _amountController.clear();
      _costController.clear();
      _supplierController.clear(); // Clear the supplier search field
      _productController.clear(); // Clear the product search field
      _totalCost = 0.0;
      _dataModified = true;
    });
  }

void _saveData() async {
  if (_selectedSupplier == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إدخال اسم المورد')),
    );
    return;
  }

  if (_addedProducts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إضافة منتجات إلى الفاتورة')),
    );
    return;
  }

  if (!_dataModified) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ البيانات بالفعل')),
    );
    return;
  }

  setState(() {
    _isSaving = true;
  });

  try {
    // Check if the supplier already exists
    if (_selectedSupplier!.id.isEmpty) {
      QuerySnapshot supplierQuery = await FirebaseFirestore.instance
          .collection('suppliers')
          .where('name', isEqualTo: _selectedSupplier!.name)
          .limit(1)
          .get();

      if (supplierQuery.docs.isNotEmpty) {
        _selectedSupplier = Supplier(
          id: supplierQuery.docs.first.id,
          name: _selectedSupplier!.name,
        );
      } else {
        // Save new supplier if not exists
        DocumentReference newSupplierRef = await FirebaseFirestore.instance.collection('suppliers').add({
          'name': _selectedSupplier!.name,
        });
        _selectedSupplier = Supplier(id: newSupplierRef.id, name: _selectedSupplier!.name);
      }
    }

    // Get the latest invoice number
    QuerySnapshot invoiceQuery = await FirebaseFirestore.instance
        .collection('buying invoices')
        .orderBy('invoiceNumber', descending: true)
        .limit(1)
        .get();

    int newInvoiceNumber = 1;
    if (invoiceQuery.docs.isNotEmpty) {
      newInvoiceNumber = invoiceQuery.docs.first['invoiceNumber'] + 1;
    }

    // Calculate the balance
    double totalSum = _calculateTotalSum();
    double paidAmount = double.parse(_paidAmountController.text);
    double balance = totalSum - paidAmount;

    // Create the invoice data
    Map<String, dynamic> invoiceData = {
      'invoiceNumber': newInvoiceNumber,
      'supplierName': _selectedSupplier!.name,
      'date': _selectedDate,
      'totalSum': totalSum,
      'products': _addedProducts,
      'paidAmount': paidAmount,
      'balance': balance,
    };

    // Save the invoice to Firestore with an auto-generated ID
    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('buying invoices')
        .add(invoiceData);

    // Update the invoice data with the generated ID
    await docRef.update({'id': docRef.id});

    // Save the invoice in the supplier's collection as a sub-collection
    DocumentReference supplierDocRef = FirebaseFirestore.instance
        .collection('suppliers')
        .doc(_selectedSupplier!.id);
    await supplierDocRef.collection('buying invoices').add({
      ...invoiceData,
      'invoiceId': docRef.id,
    });

    // Fetch all invoices of the supplier to calculate the total balance
    QuerySnapshot supplierInvoicesQuery = await supplierDocRef.collection('buying invoices').get();
    double totalBalance = supplierInvoicesQuery.docs.fold(0.0, (sum, doc) => sum + doc['balance']);

    // Update the supplier document with the total balance
    await supplierDocRef.update({'totalBalance': totalBalance});

    // Update the product quantities and save changes
    for (var product in _addedProducts) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product['product'])
          .get();

      if (query.docs.isNotEmpty) {
        for (var doc in query.docs) {
          int existingAmount = doc['quantity'];
          int newAmount = existingAmount + int.parse(product['amount']);
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .update({
            'quantity': newAmount,
          });

          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': product['date'],
            'amount': product['amount'],
            'type': 'increase',
          });
        }
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
  } catch (e) {
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error saving data: $e')),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 13.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('المشتريات',
            style: TextStyle(fontSize: 20.sp, color: Colors.white)),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.person_pin_rounded,
                              color: Colors.black.withOpacity(0.7), size: 30),
                          onPressed: _showSupplierDialog,
                        ),
                        SizedBox(width: 10.w),
                        InkWell(
                          onTap: _pickDate,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _dateController.text.isEmpty
                                    ? "${DateTime.now().toLocal()}"
                                        .split(' ')[0]
                                    : _dateController.text,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: Colors.black.withOpacity(0.7),
                                ),
                              ),
                              SizedBox(height: 5.h),
                              Text(
                                ' :التاريخ',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  color: Colors.black.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Stack(
                      children: [
                        Card(
                          margin: EdgeInsets.symmetric(
                              horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: Autocomplete<Product>(
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<Product>.empty();
                                }
                                return _products.where((Product product) {
                                  return product.name.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase());
                                });
                              },
                              displayStringForOption: (Product product) =>
                                  product.name,
                              fieldViewBuilder: (BuildContext context,
                                  TextEditingController textEditingController,
                                  FocusNode focusNode,
                                  VoidCallback onFieldSubmitted) {
                                _productController =
                                    textEditingController; // Assign the controller
                                return TextField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    suffixIcon: Icon(Icons.shopping_cart),
                                    hintText: 'ابحث عن المنتج',
                                    border: InputBorder.none,
                                  ),
                                );
                              },
                              onSelected: (Product selectedProduct) {
                                setState(() {
                                  _selectedProduct = selectedProduct;
                                  _costController.text =
                                      selectedProduct.costPrice.toStringAsFixed(
                                          2); // Set the cost price automatically
                                  _dataModified = true;
                                  _calculateTotalCost(); // Recalculate the total cost
                                });
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
                    Row(
                      children: [
                        Expanded(
                          child:Card(
                            margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
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
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال الكمية';
                                  }
                                  return null;
                                },
                                onChanged: (value) {
                                  _dataModified = true;
                                  _calculateTotalCost();
                                },
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: 20.w, vertical: 8.h),
                            elevation: 2,
                            color: Colors.orange.withOpacity(0.8),
                            child: Padding(
                              padding: EdgeInsets.all(8.w),
                              child: TextFormField(
                                controller: _costController,
                                decoration: const InputDecoration(
                                  suffixIcon: Icon(Icons.attach_money),
                                  hintText: 'أدخل التكلفة',
                                  border: InputBorder.none,
                                ),
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'يرجى إدخال التكلفة';
                                  }
                                  return null;
                                },
                                onChanged: (value) {
                                  _dataModified = true;
                                  _calculateTotalCost();
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 40.w, vertical: 5.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(0.w),
                        child: TextFormField(
                          textAlign: TextAlign.center,
                          readOnly: true,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.calculate),
                            hintText: 'الإجمالي',
                            border: InputBorder.none,
                          ),
                          controller: TextEditingController(
                              text: _totalCost.toStringAsFixed(2)),
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
                          DataColumn(
                              label: Text('المنتج', style: headTableTextStyle)),
                          DataColumn(
                              label: Text('الكمية', style: headTableTextStyle)),
                          DataColumn(
                              label:
                                  Text('التكلفة', style: headTableTextStyle)),
                          DataColumn(
                              label:
                                  Text('الإجمالي', style: headTableTextStyle)),
                          DataColumn(
                              label: Text('تعديل وحذف',
                                  style: headTableTextStyle)),
                        ],
                        rows: _addedProducts.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> product = entry.value;
                          return DataRow(cells: [
                            DataCell(Text(product['product'],
                                style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(product['amount'],
                                style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(product['cost'],
                                style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(product['totalCost'],
                                style: TextStyle(fontSize: 14.sp))),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit,
                                      color: Colors.black.withOpacity(0.7)),
                                  onPressed: () => _editProduct(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete,
                                      color: Colors.black.withOpacity(0.7)),
                                  onPressed: () => _deleteProduct(index),
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'إجمالي الفاتورة: ${_calculateTotalSum().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

class Product {
  String id;
  int randomNumber;
  String name;
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
      'sellingPrice1': sellingPrice1,
      'sellingPrice2': sellingPrice2,
      'sellingPrice3': sellingPrice3,
      'costPrice': costPrice,
      'quantity': quantity,
      'alertAmount': alertAmount,
      'image': image,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      randomNumber: map['randomNumber'],
      name: map['name'],
      sellingPrice1: map['sellingPrice1'].toDouble(),
      sellingPrice2: map['sellingPrice2'].toDouble(),
      sellingPrice3: map['sellingPrice3'].toDouble(),
      costPrice: map['costPrice'].toDouble(),
      quantity: map['quantity'],
      alertAmount: map['alertAmount'],
      image: map['image'],
    );
  }
}

class Supplier {
  String id;
  String name;

  Supplier({
    required this.id,
    required this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
    );
  }
}
