import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DecreaseProductPage extends StatefulWidget {
  const DecreaseProductPage({super.key});

  @override
  _DecreaseProductPageState createState() => _DecreaseProductPageState();
}

class _DecreaseProductPageState extends State<DecreaseProductPage> {
  final List<Product> _products = [];
  Product? _selectedProduct;
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
  double _selectedPrice = 0.0;
  double _total = 0.0;
   TextEditingController _clientNameController = TextEditingController();
   TextEditingController _productController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _newClientNameController = TextEditingController();


void _showClientNameDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('أدخل اسم العميل والمبلغ المدفوع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(hintText: 'اختر اسم العميل'),
              items: _clients.map((String client) {
                return DropdownMenuItem<String>(
                  value: client,
                  child: Text(client),
                );
              }).toList()
              ..add(
                DropdownMenuItem<String>(
                  value: 'new_client',
                  child: Text('إضافة عميل جديد'),
                ),
              ),
              onChanged: (String? newValue) {
                setState(() {
                  if (newValue == 'new_client') {
                    _clientNameController.clear();
                  } else {
                    _clientNameController.text = newValue!;
                  }
                });
              },
              value: _clientNameController.text.isNotEmpty ? _clientNameController.text : null,
            ),
            if (_clientNameController.text.isEmpty)
              TextField(
                controller: _newClientNameController,
                decoration: const InputDecoration(hintText: 'اسم العميل الجديد'),
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
                if (_clientNameController.text.isEmpty) {
                  _clientNameController.text = _newClientNameController.text;
                }
                // Save the client name and paid amount
              });
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

  Future<double> _fetchClientBalance(String clientName) async {
    DocumentSnapshot clientDoc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientName)
        .get();

    if (clientDoc.exists) {
      return clientDoc['balance'] ?? 0.0;
    } else {
      return 0.0;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchClients();
    _selectedDate = DateTime.now();
    _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
  }

  Future<double> _calculateTotalCost() async {
    double totalCost = 0.0;

    for (var product in _addedProducts) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product['product'])
          .get();

      if (query.docs.isNotEmpty) {
        var productData = query.docs.first.data() as Map<String, dynamic>;
        double costPrice = productData['costPrice'] ?? 0.0;
        int quantity = int.tryParse(product['amount'] ?? '0') ?? 0;
        totalCost += costPrice * quantity;
      }
    }

    return totalCost;
  }

  double _calculateTotalSum() {
    return _addedProducts.fold(0.0, (sum, product) => sum + product['total']);
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

  List<String> _clients = [];

  Future<void> _fetchClients() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance.collection('clients').get();
      setState(() {
        _clients = querySnapshot.docs.map((doc) => doc['clientName'] as String).toList();
      });
    } catch (e) {
      print('Error fetching clients: $e');
    }
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

  void _editProduct(int index) {
    setState(() {
      _selectedProduct = _products.firstWhere(
          (product) => product.name == _addedProducts[index]['product']);
      _selectedDate = _addedProducts[index]['date'];
      _amountController.text = _addedProducts[index]['amount'];
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
      _selectedPrice = _addedProducts[index]['selectedPrice'];
      _total = _addedProducts[index]['total'];
      _productController.text = _selectedProduct!.name; // Restore the product name field
      _editingIndex = index;
      _addedProducts.removeAt(index); // Remove the previous record
    });
  }

  void _addProduct() {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار التاريخ')),
        );
        return;
      }

      if (_selectedProduct != null && int.parse(_amountController.text) > _selectedProduct!.quantity) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الكمية المدخلة أكبر من الكمية المتاحة')),
        );
        return;
      }

      setState(() {
        bool productExists = false;
        for (var product in _addedProducts) {
          if (product['product'] == _selectedProduct!.name) {
            product['amount'] = (int.parse(product['amount']) +
                    int.parse(_amountController.text))
                .toString();
            productExists = true;
            break;
          }
        }
        if (!productExists) {
          _addedProducts.add({
            'product': _selectedProduct!.name,
            'date': _selectedDate,
            'amount': _amountController.text,
            'sellingPrice1': _selectedProduct!.sellingPrice1,
            'sellingPrice2': _selectedProduct!.sellingPrice2,
            'sellingPrice3': _selectedProduct!.sellingPrice3,
            'quantity': _selectedProduct!.quantity,
            'selectedPrice': _selectedPrice,
            'total': _total,
          });
        }
        _selectedProduct = null;
        _amountController.clear();
        _productController.clear(); // Clear the product search field
        _clientNameController.clear(); // Clear the client name search field
        _dataModified = true;
        _editingIndex = null; // Reset the editing index
      });
    }
  }

  void _deleteProduct(int index) {
    setState(() {
      _addedProducts.removeAt(index);
      _productController.clear(); // Clear the product search field
      _clientNameController.clear(); // Clear the client name search field
      _dataModified = true;
    });
  }

void _saveData() async {
  if (_clientNameController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إدخال اسم العميل')),
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
    // Get the latest invoice number
    QuerySnapshot invoiceQuery = await FirebaseFirestore.instance
        .collection('invoices')
        .orderBy('invoiceNumber', descending: true)
        .limit(1)
        .get();

    int newInvoiceNumber = 1;
    if (invoiceQuery.docs.isNotEmpty) {
      newInvoiceNumber = invoiceQuery.docs.first['invoiceNumber'] + 1;
    }

    // Calculate the total cost and profit margin
    double totalCost = await _calculateTotalCost();
    double totalSum = _calculateTotalSum();
    double profitMargin = totalSum - totalCost;

    // Calculate the balance
    double paidAmount = double.parse(_paidAmountController.text);
    double balance = totalSum - paidAmount;

    // Fetch existing client balance
    double existingBalance = await _fetchClientBalance(_clientNameController.text);
    double updatedBalance = existingBalance + balance;

    // Create the invoice data
    Map<String, dynamic> invoiceData = {
      'invoiceNumber': newInvoiceNumber,
      'clientName': _clientNameController.text,
      'date': _selectedDate,
      'totalSum': totalSum,
      'profitMargin': profitMargin,
      'paidAmount': paidAmount,
      'balance': balance,
      'products': _addedProducts,
    };

    // Save the invoice to Firestore with an auto-generated ID
    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('invoices')
        .add(invoiceData);

    // Update the invoice data with the generated ID
    await docRef.update({'id': docRef.id});

    // Update the product quantities and save changes
    for (var product in _addedProducts) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product['product'])
          .get();

      if (query.docs.isNotEmpty) {
        for (var doc in query.docs) {
          int existingAmount = doc['quantity'];
          int newAmount = existingAmount - int.parse(product['amount']);
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
            'type': 'decrease',
          });
        }
      }
    }

    // Store the client balance and invoices in a new collection
    DocumentReference clientDocRef = FirebaseFirestore.instance
        .collection('clients')
        .doc(_clientNameController.text);

    await clientDocRef.set({
      'clientName': _clientNameController.text,
      'balance': updatedBalance,
    }, SetOptions(merge: true));

    await clientDocRef.collection('invoices').add({
      'invoiceId': docRef.id,
      'invoiceNumber': newInvoiceNumber,
      'date': _selectedDate,
      'totalSum': totalSum,
      'paidAmount': paidAmount,
      'balance': balance,
      'products': _addedProducts,
    });

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
        title: Text('المبيعات',
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
                          icon: Icon(Icons.person_pin_rounded, color: Colors.black.withOpacity(0.7) , size: 30,),
                          onPressed: _showClientNameDialog,
                        ),
                        Center(
                          child: InkWell(
                            onTap: _pickDate,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3.w),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _dateController.text.isEmpty
                                        ? "${DateTime.now().toLocal()}".split(' ')[0]
                                        : _dateController.text,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      color: Colors.black.withOpacity(0.7),
                                    ),
                                  ),
                                  SizedBox(height: 5.h),
                                  Text(
                                    ' :تاريخ الفاتورة',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      color: Colors.black.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                            padding: EdgeInsets.all(3.w),
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
                              fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                                _productController = textEditingController; // Assign the controller
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
                                  _selectedPrice =
                                      selectedProduct.sellingPrice1;
                                  _total = _selectedPrice *
                                      int.parse(_amountController.text.isEmpty
                                          ? '0'
                                          : _amountController.text);
                                  _dataModified = true;
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

                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 5.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.format_list_numbered),
                          hintText: 'أدخل الكمية',
                          border: InputBorder.none,
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'يرجى إدخال الكمية';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          setState(() {
                            _total = _selectedPrice * (double.tryParse(value) ?? 0.0);
                            _dataModified = true;
                          });
                        },
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 5.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.attach_money),
                          hintText: 'اختر سعر البيع',
                          border: InputBorder.none,
                        ),
                        value: _selectedProduct != null ? '${_selectedPrice}|${_selectedProduct!.name}' : null,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedPrice = double.parse(newValue!.split('|')[0]);
                            _total = _selectedPrice * int.parse(_amountController.text.isEmpty ? '0' : _amountController.text);
                            _dataModified = true;
                          });
                        },
                        items: _selectedProduct != null
                            ? [
                                DropdownMenuItem<String>(
                                  value: '${_selectedProduct!.sellingPrice1}|${_selectedProduct!.name}',
                                  child: Text('سعر بيع 1: ${_selectedProduct!.sellingPrice1.toStringAsFixed(2)}'),
                                ),
                                DropdownMenuItem<String>(
                                  value: '${_selectedProduct!.sellingPrice2}|${_selectedProduct!.name}',
                                  child: Text('سعر بيع 2: ${_selectedProduct!.sellingPrice2.toStringAsFixed(2)}'),
                                ),
                                DropdownMenuItem<String>(
                                  value: '${_selectedProduct!.sellingPrice3}|${_selectedProduct!.name}',
                                  child: Text('سعر بيع 3: ${_selectedProduct!.sellingPrice3.toStringAsFixed(2)}'),
                                ),
                              ]
                            : [],
                        validator: (value) {
                          if (value == null) {
                            return 'يرجى اختيار سعر البيع';
                          }
                          return null;
                        },
                      ),
                    ),
                    Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 40.w, vertical: 5.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(0.w),
                        child: TextFormField(
                          textAlign: TextAlign.center, // Center the text
                          readOnly: true,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.calculate),
                            hintText: 'الإجمالي',
                            border: InputBorder.none,
                          ),
                          controller: TextEditingController(
                              text: _total.toStringAsFixed(2)),
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
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('المنتج', style: headTableTextStyle),
                          Text('الكمية', style: headTableTextStyle),
                          Text('السعر', style: headTableTextStyle),
                          Text('الاجمالي', style: headTableTextStyle),
                        ],
                      ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: ScrollPhysics(),
                      itemCount: _addedProducts.length,
                      itemBuilder: (context, index) {
                        final product = _addedProducts[index];
                        final amount = int.parse(product['amount']);
                        final total = product['total'];

                        return GestureDetector(
                          onTap: () => _editProduct(index),
                          child: Card(
                            margin: EdgeInsets.symmetric(vertical: 5.h),
                            elevation: 2,
                            color: Colors.orange.withOpacity(0.8),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 10.h),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        for (int i = 0;
                                            i < product['product'].length;
                                            i += 15)
                                          TextSpan(
                                            text: product['product'].substring(
                                                    i,
                                                    i + 15 >
                                                            product['product']
                                                                .length
                                                        ? product['product']
                                                            .length
                                                        : i + 15) +
                                                (i + 15 <
                                                        product['product']
                                                            .length
                                                    ? '\n'
                                                    : ''),
                                            style: TextStyle(fontSize: 12.sp),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(product['amount'],
                                      style: TextStyle(fontSize: 12.sp)),
                                  Text(
                                      product['selectedPrice']
                                          .toStringAsFixed(2),
                                      style: TextStyle(fontSize: 12.sp)),
                                  Text(total.toStringAsFixed(2),
                                      style: TextStyle(fontSize: 12.sp)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'إجمالي الفاتورة: ${_calculateTotalSum().toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 16.sp, fontWeight: FontWeight.bold),
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
