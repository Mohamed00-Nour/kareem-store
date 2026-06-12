import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'Data/quick_add_product_sheet.dart';
import 'home_page.dart';
import '../Buing Invoices/BuyingInvoiceListPage.dart';
import '../Buing Invoices/BuyingInvoiceDetailPage.dart';
import '../Services/invoice_number_utils.dart';
import '../Services/supplier_invoice_balance_sync_service.dart';

void _selectAllField(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  _AddProductPageState createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final List<Product> _products = [];
  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  DateTime? _selectedDate;
  final List<Map<String, dynamic>> _addedProducts = [];
  int _lineIdCounter = 0;
  final TextEditingController _dateController = TextEditingController();
  TextEditingController _productController = TextEditingController();
  bool _dataModified = false;
  bool _isSaving = false;
  bool _isFetching = true;
  double _supplierBalance = 0.0;
  Map<String, dynamic>? _lastInvoice;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
    _dateController.dispose();
    // _productController is managed by Autocomplete's internal state — do not dispose here
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    try {
      QuerySnapshot querySnapshot =
      await FirebaseFirestore.instance.collection('products').get();
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(querySnapshot.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data() as Map);
            data['id'] = doc.id;
            return Product.fromMap(data);
          }));
        _isFetching = false;
      });
    } catch (e) {
      print('Error fetching products: $e');
      if (!mounted) return;
      setState(() {
        _isFetching = false;
      });
    }
  }

  Future<void> _fetchSuppliers() async {
    try {
      QuerySnapshot querySnapshot =
      await FirebaseFirestore.instance.collection('suppliers').get();
      if (!mounted) return;
      setState(() {
        _suppliers = querySnapshot.docs
            .map((doc) => Supplier.fromMap(doc.data() as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      print('Error fetching suppliers: $e');
    }
  }

  double _calculateTotalSum() {
    return _addedProducts.fold(
        0.0, (sum, p) => sum + (p['totalCost'] as num).toDouble());
  }

  void _assignLineId(Map<String, dynamic> entry) {
    entry.putIfAbsent('lineId', () => _lineIdCounter++);
  }

  void _reorderAddedProducts(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _addedProducts.removeAt(oldIndex);
      _addedProducts.insert(newIndex, item);
      _dataModified = true;
    });
  }

  void _pickDate() async {
    final int currentYear = DateTime.now().year;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(currentYear - 1, 1, 1),
      lastDate: DateTime(currentYear + 1, 12, 31),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.orange),
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

  // ─────────────────────────────────────────────
  // Save data
  // ─────────────────────────────────────────────
  void _saveData({
    Supplier? supplier,
    double? paidAmount,
    String notes = '',
    double invoiceDiscount = 0.0,
    bool discountIsPercent = true,
  }) async {
    final Supplier? effectiveSupplier = supplier ?? _selectedSupplier;
    final double effectivePaid = paidAmount ?? 0.0;

    if (effectiveSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار اسم المورد')),
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

    setState(() => _isSaving = true);

    try {
      Supplier workingSupplier = effectiveSupplier;
      if (workingSupplier.id.isEmpty) {
        QuerySnapshot sq = await FirebaseFirestore.instance
            .collection('suppliers')
            .where('name', isEqualTo: workingSupplier.name)
            .limit(1)
            .get();
        if (sq.docs.isNotEmpty) {
          workingSupplier =
              Supplier(id: sq.docs.first.id, name: workingSupplier.name);
        } else {
          DocumentReference r = await FirebaseFirestore.instance
              .collection('suppliers')
              .add({'name': workingSupplier.name});
          workingSupplier = Supplier(id: r.id, name: workingSupplier.name);
        }
      }

      QuerySnapshot invoiceQuery = await FirebaseFirestore.instance
          .collection('buying invoices')
          .orderBy('invoiceNumber', descending: true)
          .limit(1)
          .get();
      int newInvoiceNumber = invoiceQuery.docs.isNotEmpty
          ? invoiceQuery.docs.first['invoiceNumber'] + 1
          : 1;

      final totalBeforeDiscount = _calculateTotalSum();
      final effectiveDiscountAmt = discountIsPercent
          ? totalBeforeDiscount * invoiceDiscount / 100
          : invoiceDiscount;
      final totalSum = totalBeforeDiscount - effectiveDiscountAmt;
      double balance = totalSum - effectivePaid;

      Map<String, dynamic> invoiceData = {
        'invoiceNumber': newInvoiceNumber,
        'supplierName': workingSupplier.name,
        'date': _selectedDate,
        'totalSum': totalSum,
        'paidAmount': effectivePaid,
        'balance': balance,
        'invoiceDiscount': effectiveDiscountAmt,
        'notes': notes,
        'previousBalance': _supplierBalance,
        'products': _addedProducts
            .map((p) => {
                  'product': p['product'],
                  'amount': (p['amount'] as num).toDouble(),
                  'cost': (p['cost'] as num).toDouble(),
                  'totalCost': (p['totalCost'] as num).toDouble(),
                })
            .toList(),
      };

      DocumentReference docRef = await FirebaseFirestore.instance
          .collection('buying invoices')
          .add(invoiceData);
      _lastInvoice = {...invoiceData, 'id': docRef.id};
      await docRef.update({'id': docRef.id});

      DocumentReference supplierDocRef = FirebaseFirestore.instance
          .collection('suppliers')
          .doc(workingSupplier.id);
      await supplierDocRef.collection('buying invoices').add({
        ...invoiceData,
        'invoiceId': docRef.id,
      });

      await supplierDocRef.set(
        {'name': workingSupplier.name},
        SetOptions(merge: true),
      );
      await SupplierInvoiceBalanceSyncService.syncForSupplier(
        workingSupplier.id,
      );

      for (var product in _addedProducts) {
        final productId = product['productId']?.toString() ?? '';
        DocumentSnapshot? productDoc;
        if (productId.isNotEmpty) {
          productDoc = await FirebaseFirestore.instance
              .collection('products')
              .doc(productId)
              .get();
        }
        if (productDoc == null || !productDoc.exists) {
          final query = await FirebaseFirestore.instance
              .collection('products')
              .where('name', isEqualTo: product['product'])
              .get();
          if (query.docs.isEmpty) continue;
          productDoc = query.docs.first;
        }

        final docRef = productDoc.reference;
        final docData = productDoc.data() as Map<String, dynamic>;
        double existingQty = (docData['quantity'] as num).toDouble();
        double addedQty = (product['amount'] as num).toDouble();
        Map<String, dynamic> updateData = {
          'quantity': existingQty + addedQty,
        };
        if (product['newCostPrice'] != null) {
          updateData['costPrice'] =
              (product['newCostPrice'] as num).toDouble();
        }
        if (product['newSellingPrice1'] != null) {
          updateData['sellingPrice1'] =
              (product['newSellingPrice1'] as num).toDouble();
        }
        if (product['newSellingPrice2'] != null) {
          updateData['sellingPrice2'] =
              (product['newSellingPrice2'] as num).toDouble();
        }
        if (product['newSellingPrice3'] != null) {
          updateData['sellingPrice3'] =
              (product['newSellingPrice3'] as num).toDouble();
        }
        await docRef.update(updateData);
        await docRef.collection('changes').add({
          'date': product['date'],
          'amount': addedQty,
          'type': 'increase',
        });
      }

      DocumentReference boxDocRef =
          FirebaseFirestore.instance.collection('box').doc('mainBox');
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot boxSnapshot = await transaction.get(boxDocRef);
        if (boxSnapshot.exists) {
          double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
          transaction
              .update(boxDocRef, {'value': currentBoxValue - effectivePaid});
        } else {
          transaction.set(boxDocRef, {'value': -effectivePaid});
        }
        await boxDocRef.collection('changes').add({
          'date': FieldValue.serverTimestamp(),
          'value': effectivePaid,
          'type': 'decrement',
          'name': workingSupplier.name,
          'invoiceNumber': newInvoiceNumber,
        });
      });

      if (!mounted) return;
      setState(() {
        _dataModified = false;
        _isSaving = false;
        _selectedSupplier = workingSupplier;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح')));
    } catch (e) {
      print(e);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving data: $e')));
    }
  }

  Future<double> _fetchSupplierBalance(String supplierName) async {
    final name = supplierName.trim();
    if (name.isEmpty) return 0.0;
    try {
      final query = await FirebaseFirestore.instance
          .collection('suppliers')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return invoiceNum(query.docs.first['totalBalance']);
      }
    } catch (e) {
      print('Error fetching supplier balance: $e');
    }
    return 0.0;
  }

  Future<void> _fetchAndSetSupplierBalance(String supplierName) async {
    final bal = await _fetchSupplierBalance(supplierName);
    if (!mounted) return;
    setState(() => _supplierBalance = bal);
  }

  Future<void> _syncProductPricesToFirestore({
    required Product product,
    required double sp1,
    required double sp2,
    required double sp3,
    required String sp1Text,
    required String sp2Text,
    required String sp3Text,
  }) async {
    final updates = <String, dynamic>{};
    if (sp1Text.trim().isNotEmpty &&
        (sp1 - product.sellingPrice1).abs() > 0.001) {
      updates['sellingPrice1'] = sp1;
    }
    if (sp2Text.trim().isNotEmpty &&
        (sp2 - product.sellingPrice2).abs() > 0.001) {
      updates['sellingPrice2'] = sp2;
    }
    if (sp3Text.trim().isNotEmpty &&
        (sp3 - product.sellingPrice3).abs() > 0.001) {
      updates['sellingPrice3'] = sp3;
    }
    if (updates.isEmpty) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product.name)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return;
      await query.docs.first.reference.update(updates);

      if (!mounted) return;
      setState(() {
        final idx = _products.indexWhere((p) => p.name == product.name);
        if (idx == -1) return;
        if (updates.containsKey('sellingPrice1')) {
          _products[idx].sellingPrice1 = sp1;
        }
        if (updates.containsKey('sellingPrice2')) {
          _products[idx].sellingPrice2 = sp2;
        }
        if (updates.containsKey('sellingPrice3')) {
          _products[idx].sellingPrice3 = sp3;
        }
      });
    } catch (e) {
      debugPrint('Failed to sync product prices: $e');
    }
  }

  Future<void> _addNewProductInline({String? initialName}) async {
    final result = await showQuickAddProductSheet(
      context,
      initialName: initialName,
    );
    if (result == null || !mounted) return;

    final product = Product.fromMap(result);
    setState(() {
      final idx = _products.indexWhere((p) => p.id == product.id);
      if (idx >= 0) {
        _products[idx] = product;
      } else {
        _products.add(product);
      }
    });
    _showProductSheet(newProduct: product);
  }

  String _normalizeProductName(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  Future<String?> _resolveLineProductDocId(Map<String, dynamic> line) async {
    final productId = line['productId']?.toString() ?? '';
    if (productId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();
      if (doc.exists) return productId;
    }
    final name = line['product']?.toString() ?? '';
    if (name.isEmpty) return null;
    final query = await FirebaseFirestore.instance
        .collection('products')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  Future<void> _showChangeLineProductNameDialog(int index) async {
    final line = _addedProducts[index];
    final oldName = line['product']?.toString() ?? '';

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: oldName);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تغيير اسم المنتج',
                style:
                    TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الاسم الحالي: $oldName',
                      style:
                          TextStyle(fontSize: 13.sp, color: Colors.black54)),
                  SizedBox(height: 6.h),
                  Text(
                    'يتم تغيير الاسم فقط — التكلفة والأسعار والكمية تبقى كما هي',
                    style: TextStyle(fontSize: 12.sp, color: Colors.black45),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: nameCtrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: 'الاسم الجديد',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: TextStyle(fontSize: 14.sp)),
              ),
              TextButton(
                onPressed: () {
                  final n = _normalizeProductName(nameCtrl.text);
                  if (n.isEmpty) return;
                  Navigator.pop(ctx, n);
                },
                child: Text('حفظ',
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800)),
              ),
            ],
          ),
        );
      },
    );

    if (newName == null || !mounted) return;
    if (newName == oldName) return;

    for (var i = 0; i < _addedProducts.length; i++) {
      if (i != index && _addedProducts[i]['product'] == newName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('هذا المنتج موجود بالفعل في الفاتورة')),
        );
        return;
      }
    }

    try {
      final docId = await _resolveLineProductDocId(line);
      if (docId != null) {
        final nameTaken = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: newName)
            .limit(1)
            .get();
        if (nameTaken.docs.isNotEmpty && nameTaken.docs.first.id != docId) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('اسم المنتج مستخدم بالفعل في المخزون')),
          );
          return;
        }
        await FirebaseFirestore.instance
            .collection('products')
            .doc(docId)
            .update({'name': newName});
      } else {
        final nameTaken = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: newName)
            .limit(1)
            .get();
        if (nameTaken.docs.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('اسم المنتج مستخدم بالفعل في المخزون')),
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _addedProducts.length; i++) {
          if (_addedProducts[i]['product'] != oldName) continue;
          final updated = Map<String, dynamic>.from(_addedProducts[i]);
          updated['product'] = newName;
          if (docId != null) updated['productId'] = docId;
          _addedProducts[i] = updated;
        }

        final catalogIdx = _products.indexWhere(
          (p) =>
              (docId != null && p.id == docId) ||
              (docId == null && p.name == oldName),
        );
        if (catalogIdx >= 0) {
          _products[catalogIdx].name = newName;
          if (docId != null) _products[catalogIdx].id = docId;
        }
        _dataModified = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير اسم المنتج')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تغيير الاسم: $e')),
      );
    }
  }

  // ─────────────────────────────────────────────
  // Product bottom sheet (buying)
  // ─────────────────────────────────────────────
  void _showProductSheet({int? editIndex, Product? newProduct}) {
    final Product product = editIndex != null
        ? (_products.firstWhere(
            (p) => p.name == _addedProducts[editIndex]['product'],
            orElse: () => newProduct!))
        : newProduct!;

    double qty = editIndex != null
        ? ((_addedProducts[editIndex]['amount'] as num).toDouble())
        : 1.0;
    double newCost = editIndex != null
        ? ((_addedProducts[editIndex]['cost'] as num).toDouble())
        : product.costPrice;
    double sp1 = editIndex != null
        ? ((_addedProducts[editIndex]['newSellingPrice1'] ??
                product.sellingPrice1) as num)
            .toDouble()
        : product.sellingPrice1;
    double sp2 = editIndex != null
        ? ((_addedProducts[editIndex]['newSellingPrice2'] ??
                product.sellingPrice2) as num)
            .toDouble()
        : product.sellingPrice2;
    double sp3 = editIndex != null
        ? ((_addedProducts[editIndex]['newSellingPrice3'] ??
                product.sellingPrice3) as num)
            .toDouble()
        : product.sellingPrice3;
    DateTime? expiryDate = editIndex != null
        ? (_addedProducts[editIndex]['expiryDate'] as DateTime?)
        : null;
    bool removeProduct = false;

    double weightedCost = product.quantity > 0
        ? (product.quantity * product.costPrice + qty * newCost) /
            (product.quantity + qty)
        : newCost;

    final qtyCtrl = TextEditingController(text: qty.toStringAsFixed(1));
    final newCostCtrl =
        TextEditingController(text: newCost.toStringAsFixed(2));
    final sp1Ctrl = TextEditingController(text: sp1.toStringAsFixed(2));
    final sp2Ctrl = TextEditingController(text: sp2.toStringAsFixed(2));
    final sp3Ctrl = TextEditingController(text: sp3.toStringAsFixed(2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _selectAllField(qtyCtrl);
        });
        return StatefulBuilder(builder: (ctx, setSheet) {
          double totalCost = qty * newCost;
          weightedCost = product.quantity > 0
              ? (product.quantity * product.costPrice + qty * newCost) /
                  (product.quantity + qty)
              : newCost;
          double avgSell = (sp1 + sp2 + sp3) / 3;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16.w,
                right: 16.w,
                top: 20.h,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(product.name,
                          style: TextStyle(
                              fontSize: 17.sp, fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: 14.h),

                    // ── Row 1: الكمية الموجوده | الكمية الجديده | اجمالي التكلفه ──
                    Row(children: [
                      Expanded(
                          child: _BuySheetCol(
                              label: 'اجمالي التكلفه',
                              value: totalCost.toStringAsFixed(1))),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(children: [
                          Text('الكمية الجديده',
                              style: TextStyle(
                                  fontSize: 11.sp, color: Colors.black54)),
                          SizedBox(height: 4.h),
                          TextField(
                            controller: qtyCtrl,
                            textAlign: TextAlign.center,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r)),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 8.h),
                            ),
                            onTap: () => _selectAllField(qtyCtrl),
                            onChanged: (v) => setSheet(
                                () => qty = double.tryParse(v) ?? qty),
                          ),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove, size: 16.sp),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setSheet(() {
                                    if (qty > 0.5) {
                                      qty -= 1;
                                      qtyCtrl.text = qty.toStringAsFixed(1);
                                    }
                                  }),
                                ),
                                IconButton(
                                  icon: Icon(Icons.add, size: 16.sp),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setSheet(() {
                                    qty += 1;
                                    qtyCtrl.text = qty.toStringAsFixed(1);
                                  }),
                                ),
                              ]),
                        ]),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                          child: _BuySheetCol(
                              label: 'الكمية الموجوده',
                              value: product.quantity.toStringAsFixed(1),
                              valueColor: Colors.black54)),
                    ]),
                    SizedBox(height: 12.h),

                    // ── Row 2: سعر الشراء القديم | سعر الشراء الجديد | المتوسط الحسابي ──
                    Row(children: [
                      Expanded(
                          child: _BuySheetCol(
                              label: 'المتوسط الحسابي',
                              value: weightedCost.toStringAsFixed(1))),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(children: [
                          Text('سعر الشراء الجديد',
                              style: TextStyle(
                                  fontSize: 11.sp, color: Colors.black54)),
                          SizedBox(height: 4.h),
                          TextField(
                            controller: newCostCtrl,
                            textAlign: TextAlign.center,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r)),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 8.h),
                            ),
                            onTap: () => _selectAllField(newCostCtrl),
                            onChanged: (v) => setSheet(
                                () => newCost = double.tryParse(v) ?? newCost),
                          ),
                        ]),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                          child: _BuySheetCol(
                              label: 'سعر الشراء القديم',
                              value: product.costPrice.toStringAsFixed(1),
                              valueColor: Colors.black54)),
                    ]),
                    SizedBox(height: 8.h),

                    // احسب (weighted cost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r)),
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                        ),
                        onPressed: () => setSheet(() {
                          weightedCost = product.quantity > 0
                              ? (product.quantity * product.costPrice +
                                      qty * newCost) /
                                  (product.quantity + qty)
                              : newCost;
                        }),
                        child: Text('احسب',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // ── Row 3: سعر البيع القديم | 1 | 2 | 3 | المتوسط ──
                    Row(children: [
                      Expanded(
                          child: _BuySheetCol(
                              label: 'المتوسط الحسابي',
                              value: avgSell.toStringAsFixed(1))),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Column(children: [
                          Text('سعر البيع 3',
                              style: TextStyle(
                                  fontSize: 10.sp, color: Colors.black54)),
                          SizedBox(height: 4.h),
                          TextField(
                            controller: sp3Ctrl,
                            textAlign: TextAlign.center,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r)),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 6.h),
                            ),
                            onTap: () => _selectAllField(sp3Ctrl),
                            onChanged: (v) =>
                                setSheet(() => sp3 = double.tryParse(v) ?? sp3),
                          ),
                        ]),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Column(children: [
                          Text('سعر البيع 2',
                              style: TextStyle(
                                  fontSize: 10.sp, color: Colors.black54)),
                          SizedBox(height: 4.h),
                          TextField(
                            controller: sp2Ctrl,
                            textAlign: TextAlign.center,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r)),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 6.h),
                            ),
                            onTap: () => _selectAllField(sp2Ctrl),
                            onChanged: (v) =>
                                setSheet(() => sp2 = double.tryParse(v) ?? sp2),
                          ),
                        ]),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Column(children: [
                          Text('سعر البيع 1',
                              style: TextStyle(
                                  fontSize: 10.sp, color: Colors.black54)),
                          SizedBox(height: 4.h),
                          TextField(
                            controller: sp1Ctrl,
                            textAlign: TextAlign.center,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r)),
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 6.h),
                            ),
                            onTap: () => _selectAllField(sp1Ctrl),
                            onChanged: (v) =>
                                setSheet(() => sp1 = double.tryParse(v) ?? sp1),
                          ),
                        ]),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                          child: _BuySheetCol(
                              label: 'سعر البيع القديم',
                              value: product.sellingPrice1.toStringAsFixed(1),
                              valueColor: Colors.black54)),
                    ]),
                    SizedBox(height: 8.h),

                    // احسب (avg sell)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r)),
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                        ),
                        onPressed: () => setSheet(() {
                          avgSell = (sp1 + sp2 + sp3) / 3;
                        }),
                        child: Text('احسب',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // ── تاريخ الانتهاء ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: ctx,
                              initialDate: expiryDate ??
                                  DateTime.now()
                                      .add(const Duration(days: 365)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(DateTime.now().year + 10),
                              builder: (c, child) => Theme(
                                data: ThemeData.light().copyWith(
                                    colorScheme: const ColorScheme.light(
                                        primary: Colors.orange)),
                                child: child!,
                              ),
                            );
                            if (picked != null)
                              setSheet(() => expiryDate = picked);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              expiryDate != null
                                  ? "${expiryDate!.toLocal()}".split(' ')[0]
                                  : "${DateTime.now().toLocal()}".split(' ')[0],
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ),
                        ),
                        Text('تاريخ الانتهاء',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // ── إلغاء المنتج ──
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Checkbox(
                            value: removeProduct,
                            activeColor: Colors.red,
                            onChanged: (v) =>
                                setSheet(() => removeProduct = v ?? false),
                          ),
                          Row(children: [
                            Icon(Icons.close, color: Colors.red, size: 16.sp),
                            SizedBox(width: 4.w),
                            Text('إلغاء المنتج من القائمه',
                                style: TextStyle(
                                    fontSize: 13.sp, color: Colors.red)),
                          ]),
                        ]),
                    SizedBox(height: 14.h),

                    // ── Action buttons ──
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('تراجع',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            if (removeProduct) {
                              if (editIndex != null) {
                                setState(() {
                                  _addedProducts.removeAt(editIndex);
                                  _dataModified = true;
                                });
                              }
                              return;
                            }
                            await _syncProductPricesToFirestore(
                              product: product,
                              sp1: sp1,
                              sp2: sp2,
                              sp3: sp3,
                              sp1Text: sp1Ctrl.text,
                              sp2Text: sp2Ctrl.text,
                              sp3Text: sp3Ctrl.text,
                            );
                            if (!mounted) return;
                            final entry = {
                              'product': product.name,
                              'productId': product.id,
                              'date': _selectedDate,
                              'amount': qty,
                              'cost': newCost,
                              'totalCost': qty * newCost,
                              'newCostPrice': newCost,
                              'newSellingPrice1': sp1,
                              'newSellingPrice2': sp2,
                              'newSellingPrice3': sp3,
                              'expiryDate': expiryDate,
                            };
                            if (editIndex != null) {
                              final lineId = _addedProducts[editIndex]['lineId'];
                              if (lineId != null) entry['lineId'] = lineId;
                            }
                            setState(() {
                              if (editIndex != null) {
                                _addedProducts[editIndex] = entry;
                              } else {
                                int idx = _addedProducts.indexWhere(
                                    (p) => p['product'] == product.name);
                                if (idx != -1) {
                                  final lineId = _addedProducts[idx]['lineId'];
                                  if (lineId != null) entry['lineId'] = lineId;
                                  _addedProducts[idx] = entry;
                                } else {
                                  _assignLineId(entry);
                                  _addedProducts.add(entry);
                                }
                              }
                              _dataModified = true;
                            });
                          },
                          child: Text('متابعة',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  // ─────────────────────────────────────────────
  // Checkout sheet (حفظ)
  // ─────────────────────────────────────────────
  void _showCheckoutSheet() {
    if (_addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إضافة منتجات إلى الفاتورة')));
      return;
    }

    Supplier? checkoutSupplier = _selectedSupplier;
    String notes = '';
    bool addingNewSupplier = false;
    String supplierSearch = '';
    String? supplierDuplicateWarning;
    double? checkoutSupplierBalance =
        checkoutSupplier != null ? _supplierBalance : null;
    bool loadingCheckoutSupplierBalance = false;
    double invoiceDiscount = 0.0;
    bool discountIsPercent = true;
    final paidCtrl = TextEditingController(
      text: _calculateTotalSum().toStringAsFixed(2),
    );
    final discountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final newSupplierCtrl = TextEditingController();
    final supplierSearchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> loadCheckoutSupplierBalance(String supplierName) async {
            if (supplierName.trim().isEmpty) {
              setSheet(() {
                checkoutSupplierBalance = null;
                loadingCheckoutSupplierBalance = false;
              });
              return;
            }
            setSheet(() {
              loadingCheckoutSupplierBalance = true;
              checkoutSupplierBalance = null;
            });
            final bal = await _fetchSupplierBalance(supplierName.trim());
            setSheet(() {
              checkoutSupplierBalance = bal;
              loadingCheckoutSupplierBalance = false;
            });
          }

          if (checkoutSupplier != null &&
              checkoutSupplier!.name.trim().isNotEmpty &&
              checkoutSupplierBalance == null &&
              !loadingCheckoutSupplierBalance) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCheckoutSupplierBalance(checkoutSupplier!.name);
            });
          }

          double totalSum = _calculateTotalSum();
          double effectiveDiscountAmt = discountIsPercent
              ? totalSum * invoiceDiscount / 100
              : invoiceDiscount;
          double totalAfterDiscount = totalSum - effectiveDiscountAmt;
          double paid = double.tryParse(paidCtrl.text) ?? 0.0;
          double remaining = paid - totalAfterDiscount;

          void syncPaidToTotal() {
            final sum = _calculateTotalSum();
            final disc = discountIsPercent
                ? sum * invoiceDiscount / 100
                : invoiceDiscount;
            paidCtrl.text = (sum - disc).toStringAsFixed(2);
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16.w,
                right: 16.w,
                top: 16.h,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الإجمالي',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: 12.w),
                            padding: EdgeInsets.symmetric(
                                vertical: 10.h, horizontal: 12.w),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(totalAfterDiscount.toStringAsFixed(2),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Text('الخصم',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold)),
                        SizedBox(width: 8.w),
                        SizedBox(
                          width: 80.w,
                          child: TextField(
                            controller: discountCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              hintText: '0',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.r)),
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 8.h, horizontal: 6.w),
                            ),
                            onTap: () => _selectAllField(discountCtrl),
                            onChanged: (v) => setSheet(() {
                              invoiceDiscount = double.tryParse(v) ?? 0.0;
                              syncPaidToTotal();
                            }),
                          ),
                        ),
                        SizedBox(width: 6.w),
                        GestureDetector(
                          onTap: () => setSheet(() {
                            discountIsPercent = !discountIsPercent;
                            syncPaidToTotal();
                          }),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 9.h),
                            decoration: BoxDecoration(
                              color: discountIsPercent
                                  ? Colors.orange.shade100
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text('%',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المدفوع',
                            style: TextStyle(
                                fontSize: 13.sp, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Row(children: [
                            SizedBox(width: 12.w),
                            Expanded(
                              child: TextField(
                                controller: paidCtrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(fontSize: 16.sp),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r)),
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 8.w),
                                ),
                                onChanged: (_) => setSheet(() {}),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                          vertical: 10.h, horizontal: 10.w),
                      decoration: BoxDecoration(
                        color: remaining >= 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        border: Border.all(
                            color: remaining >= 0
                                ? Colors.green.shade300
                                : Colors.red.shade300),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الباقي',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.bold)),
                            Text(remaining.toStringAsFixed(2),
                                style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: remaining >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700)),
                          ]),
                    ),
                    SizedBox(height: 14.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('المورد',
                          style: TextStyle(
                              fontSize: 13.sp, fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: 8.h),
                    // ── Supplier search + add icon ──
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: supplierSearchCtrl,
                            textDirection: TextDirection.rtl,
                            decoration: InputDecoration(
                              hintText: 'ابحث عن مورد...',
                              hintTextDirection: TextDirection.rtl,
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.black54),
                              suffixIcon: supplierSearch.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: Colors.black54),
                                      onPressed: () {
                                        supplierSearchCtrl.clear();
                                        setSheet(() => supplierSearch = '');
                                      },
                                    )
                                  : null,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12.w, vertical: 10.h),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.r),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade400),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.r),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade400),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.r),
                                borderSide:
                                    const BorderSide(color: Colors.black87),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            onChanged: (v) =>
                                setSheet(() => supplierSearch = v.trim()),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Tooltip(
                          message: 'إضافة مورد جديد',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10.r),
                            onTap: () => setSheet(
                                () => addingNewSupplier = !addingNewSupplier),
                            child: Container(
                              padding: EdgeInsets.all(10.w),
                              decoration: BoxDecoration(
                                color: addingNewSupplier
                                    ? Colors.black87
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Icon(
                                Icons.person_add_alt_1,
                                color: addingNewSupplier
                                    ? Colors.white
                                    : Colors.black87,
                                size: 22.sp,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ── Add new supplier inline field ──
                    if (addingNewSupplier) ...[
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newSupplierCtrl,
                              textDirection: TextDirection.rtl,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'اسم المورد الجديد',
                                hintTextDirection: TextDirection.rtl,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12.w, vertical: 10.h),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.r),
                                  borderSide: const BorderSide(
                                      color: Colors.black87),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.r),
                                  borderSide: const BorderSide(
                                      color: Colors.black87, width: 2),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.r)),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 14.w, vertical: 12.h),
                            ),
                            onPressed: () {
                              final newName = newSupplierCtrl.text.trim();
                              if (newName.isEmpty) return;
                              final alreadyExists = _suppliers.any((s) =>
                                  s.name.toLowerCase() ==
                                  newName.toLowerCase());
                              if (alreadyExists) {
                                final existing = _suppliers.firstWhere((s) =>
                                    s.name.toLowerCase() ==
                                    newName.toLowerCase());
                                setSheet(() {
                                  checkoutSupplier = existing;
                                  supplierDuplicateWarning =
                                      'هذا المورد موجود بالفعل';
                                });
                              } else {
                                final newSupplier =
                                    Supplier(id: '', name: newName);
                                setSheet(() {
                                  _suppliers.add(newSupplier);
                                  checkoutSupplier = newSupplier;
                                  addingNewSupplier = false;
                                  supplierDuplicateWarning = null;
                                  newSupplierCtrl.clear();
                                });
                              }
                            },
                            child: Text('إضافة',
                                style: TextStyle(fontSize: 13.sp)),
                          ),
                        ],
                      ),
                    ],
                    // ── Duplicate warning ──
                    if (supplierDuplicateWarning != null) ...[
                      SizedBox(height: 8.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                              color: Colors.orange.shade300, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.orange.shade700, size: 16.sp),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                supplierDuplicateWarning!,
                                style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 8.h),
                    // ── Supplier list ──
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.22),
                      child: Builder(builder: (_) {
                        final filtered = supplierSearch.isEmpty
                            ? _suppliers
                            : _suppliers
                                .where((s) => s.name
                                    .toLowerCase()
                                    .contains(supplierSearch.toLowerCase()))
                                .toList();
                        if (filtered.isEmpty) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 10.h),
                            child: Text(
                              'لا يوجد مورد بهذا الاسم',
                              style: TextStyle(
                                  fontSize: 13.sp, color: Colors.black54),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final isSelected =
                                checkoutSupplier?.name == s.name;
                            return InkWell(
                              onTap: () {
                                setSheet(() => checkoutSupplier = s);
                                loadCheckoutSupplierBalance(s.name);
                                _fetchAndSetSupplierBalance(s.name);
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12.w, vertical: 10.h),
                                margin: EdgeInsets.symmetric(vertical: 3.h),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.black87
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.storefront_outlined,
                                      size: 18.sp,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black54,
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle,
                                          size: 18.sp, color: Colors.orange),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                    if (checkoutSupplier != null &&
                        checkoutSupplier!.name.trim().isNotEmpty) ...[
                      SizedBox(height: 10.h),
                      Builder(
                        builder: (_) {
                          final balanceBefore = checkoutSupplierBalance ?? 0.0;
                          final invoiceUnpaid = totalAfterDiscount - paid;
                          final balanceAfter = balanceBefore - invoiceUnpaid;
                          TextStyle balanceStyle(double amount) => TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: amount > 0
                                    ? Colors.red.shade700
                                    : Colors.black87,
                              );
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10.r),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.4)),
                            ),
                            child: loadingCheckoutSupplierBalance
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 18.w,
                                        height: 18.w,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        'جاري تحميل الرصيد...',
                                        style: TextStyle(fontSize: 13.sp),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'الرصيد قبل الفاتورة: ${invoiceAmount(balanceBefore)} ج.م',
                                        textAlign: TextAlign.center,
                                        style: balanceStyle(balanceBefore),
                                      ),
                                      SizedBox(height: 6.h),
                                      Text(
                                        'الرصيد بعد الفاتورة (المتبقي للمورد): ${invoiceAmount(balanceAfter)} ج.م',
                                        textAlign: TextAlign.center,
                                        style: balanceStyle(balanceAfter)
                                            .copyWith(fontSize: 14.sp),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ],
                    SizedBox(height: 10.h),
                    TextField(
                      controller: notesCtrl,
                      textAlign: TextAlign.right,
                      onChanged: (v) => notes = v,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'بيانات إضافية للفاتورة',
                        hintStyle:
                            TextStyle(fontSize: 12.sp, color: Colors.grey),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.r)),
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 10.h, horizontal: 12.w),
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('تراجع',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          onPressed: () async {
                            Supplier? finalSupplier = checkoutSupplier;
                            if (addingNewSupplier) {
                              final name = newSupplierCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('يرجى إدخال اسم المورد')));
                                return;
                              }
                              finalSupplier = Supplier(id: '', name: name);
                            }
                            if (finalSupplier == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('يجب اختيار المورد')));
                              return;
                            }
                            // Read controller values BEFORE pop disposes them
                            final double paidAmount =
                                double.tryParse(paidCtrl.text) ?? 0.0;
                            final String savedNotes = notesCtrl.text;
                            final double savedDiscount = invoiceDiscount;
                            final bool savedDiscountIsPercent = discountIsPercent;
                            Navigator.pop(ctx);
                            setState(() => _selectedSupplier = finalSupplier);
                            await _fetchAndSetSupplierBalance(finalSupplier!.name);
                            _saveData(
                              supplier: finalSupplier,
                              paidAmount: paidAmount,
                              notes: savedNotes,
                              invoiceDiscount: savedDiscount,
                              discountIsPercent: savedDiscountIsPercent,
                            );
                          },
                          child: Text('متابعة',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }


  Widget _buildDrawer() {
    return Drawer(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(children: [
          Container(
            width: double.infinity,
            color: Colors.black.withOpacity(0.75),
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16.h,
                bottom: 16.h,
                right: 16.w),
            child: Text('المشتريات',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              children: [
                ListTile(
                  leading: Icon(Icons.add_box_outlined, size: 22.sp),
                  title: Text('اضافة منتج جديد',
                      style: TextStyle(fontSize: 15.sp)),
                  onTap: () {
                    Navigator.pop(context);
                    _addNewProductInline();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.print_outlined, size: 22.sp),
                  title: Text('اعادة طباعة الفاتورة',
                      style: TextStyle(fontSize: 15.sp)),
                  onTap: () {
                    Navigator.pop(context);
                    if (_lastInvoice != null) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BuyingInvoiceDetailPage(
                                  invoice: _lastInvoice!)));
                    } else {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const BuyingInvoiceListPage()));
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.edit_document, size: 22.sp),
                  title: Text('تعديل فاتورة مشتريات',
                      style: TextStyle(fontSize: 15.sp)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BuyingInvoiceListPage()));
                  },
                ),
                ListTile(
                  leading: Icon(Icons.file_download_outlined, size: 22.sp),
                  title: Text('استيراد البيانات من طلب شراء',
                      style: TextStyle(fontSize: 15.sp)),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: Text('قريبًا',
                              style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold)),
                          content: Text(
                              'ميزة استيراد طلبات الشراء ستكون متاحة قريبًا.',
                              style: TextStyle(fontSize: 14.sp)),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('حسنًا',
                                    style: TextStyle(
                                        color: Colors.orange))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalSum = _calculateTotalSum();
    double totalQty = _addedProducts.fold(
        0.0, (s, p) => s + (p['amount'] as num).toDouble());

    return WillPopScope(
      onWillPop: () => HomePage.confirmNavigateBack(context),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xffeeeced),
          endDrawer: _buildDrawer(),
          appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text('المشتريات',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold)),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: Icon(Icons.menu, color: Colors.white, size: 26.sp),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // ── Date row ──
                Container(
                  color: Colors.white,
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              vertical: 10.h, horizontal: 12.w),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _dateController.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15.sp, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Text('تاريخ الفاتورة',
                        style: TextStyle(
                            fontSize: 14.sp, fontWeight: FontWeight.bold)),
                  ]),
                ),

                // ── Search row ──
                Container(
                  color: Colors.white,
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.save_outlined,
                          color: Colors.blue.shade700, size: 30.sp),
                      onPressed: _showCheckoutSheet,
                      tooltip: 'حفظ الفاتورة',
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline,
                          color: Colors.orange.shade800, size: 26.sp),
                      onPressed: () => _addNewProductInline(
                        initialName: _productController.text.trim().isEmpty
                            ? null
                            : _productController.text.trim(),
                      ),
                      tooltip: 'إضافة منتج جديد',
                    ),
                    Expanded(
                      child: Container(
                        height: 42.h,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: _isFetching
                            ? Center(
                                child: SizedBox(
                                    width: 20.w,
                                    height: 20.h,
                                    child: const CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : Autocomplete<Product>(
                                optionsBuilder: (TextEditingValue val) {
                                  if (val.text.isEmpty) {
                                    return const Iterable<Product>.empty();
                                  }
                                  return _products.where((p) =>
                                      !p.retail &&
                                      p.name
                                          .toLowerCase()
                                          .contains(val.text.toLowerCase()));
                                },
                                displayStringForOption: (p) => p.name,
                                fieldViewBuilder: (ctx, ctrl, focus, _) {
                                  _productController = ctrl;
                                  return TextField(
                                    controller: ctrl,
                                    focusNode: focus,
                                    textAlign: TextAlign.right,
                                    decoration: InputDecoration(
                                      hintText:
                                          'ابحث عن منتج أو استخدم الكاميرا',
                                      hintStyle: TextStyle(
                                          fontSize: 12.sp,
                                          color: Colors.grey),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10.w, vertical: 11.h),
                                    ),
                                  );
                                },
                                onSelected: (Product selected) {
                                  _productController.clear();
                                  _showProductSheet(newProduct: selected);
                                },
                              ),
                      ),
                    ),
                    SizedBox(width: 4.w),
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner,
                          color: Colors.black87, size: 26.sp),
                      onPressed: () {},
                    ),
                  ]),
                ),

                // ── Supplier badge ──
                if (_selectedSupplier != null)
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 12.w, vertical: 5.h),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => setState(() => _selectedSupplier = null),
                        child: Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              color: Colors.red, size: 16.sp),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      if (_supplierBalance > 0) ...[
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.red, size: 18.sp),
                        SizedBox(width: 4.w),
                      ],
                      Expanded(
                        child: Text(_selectedSupplier!.name,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold)),
                      ),
                      if (_supplierBalance > 0)
                        Text(
                          'رصيد: ${_supplierBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 11.sp, color: Colors.red.shade700),
                        ),
                    ]),
                  ),

                // ── Table headers ──
                Container(
                  color: Colors.grey.shade200,
                  padding: EdgeInsets.symmetric(
                      horizontal: 10.w, vertical: 7.h),
                  child: Row(children: [
                    SizedBox(width: 28.w),
                    Expanded(
                        flex: 3,
                        child: Text('الإجمالي',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('الكمية',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('التكلفه',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('المنتج',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold))),
                  ]),
                ),

                // ── Products list ──
                Expanded(
                  child: _addedProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 60.sp,
                                  color: Colors.grey.shade400),
                              SizedBox(height: 8.h),
                              Text('ابحث عن منتج وأضفه للفاتورة',
                                  style: TextStyle(
                                      fontSize: 14.sp,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding:
                              EdgeInsets.only(top: 4.h, bottom: 80.h),
                          buildDefaultDragHandles: false,
                          itemCount: _addedProducts.length,
                          onReorder: _reorderAddedProducts,
                          itemBuilder: (context, index) {
                            final p = _addedProducts[index];
                            final amount =
                                (p['amount'] as num).toDouble();
                            final cost = (p['cost'] as num).toDouble();
                            final totalCost =
                                (p['totalCost'] as num).toDouble();
                            return Material(
                              key: ValueKey(p['lineId'] ?? index),
                              color: Colors.transparent,
                              child: GestureDetector(
                              onTap: () =>
                                  _showProductSheet(editIndex: index),
                              onLongPress: () =>
                                  _showChangeLineProductNameDialog(index),
                              child: Container(
                                margin: EdgeInsets.symmetric(
                                    horizontal: 8.w, vertical: 3.h),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(10.r),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black
                                            .withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ],
                                ),
                                child: Row(children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Container(
                                      width: 28.w,
                                      alignment: Alignment.center,
                                      child: Icon(Icons.drag_handle,
                                          color: Colors.grey.shade400,
                                          size: 20.sp),
                                    ),
                                  ),
                                  Expanded(
                                      flex: 3,
                                      child: Text(
                                          totalCost.toStringAsFixed(1),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 13.sp,
                                              fontWeight:
                                                  FontWeight.bold))),
                                  Expanded(
                                      flex: 2,
                                      child: Text(
                                          amount.toStringAsFixed(1),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 13.sp))),
                                  Expanded(
                                      flex: 2,
                                      child: Text(cost.toStringAsFixed(1),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 13.sp))),
                                  Expanded(
                                    flex: 3,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: 12.h, horizontal: 6.w),
                                      child: Text(p['product'],
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 13.sp,
                                              fontWeight:
                                                  FontWeight.w600)),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            );
                          },
                        ),
                ),
              ],
            ),

            // ── Bottom bar ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2))
                  ],
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: 12.w, vertical: 10.h),
                child: Row(children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ج.م',
                          style: TextStyle(
                              fontSize: 11.sp, color: Colors.black54)),
                      Text(totalQty.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade600)),
                    ],
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        totalSum.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  IconButton(
                    icon: Icon(Icons.grid_view_rounded,
                        color: Colors.black54, size: 28.sp),
                    onPressed: _showCheckoutSheet,
                  ),
                ]),
              ),
            ),

            if (_isSaving)
              Container(
                color: Colors.black.withOpacity(0.45),
                child: Center(
                  child: CircularProgressIndicator(
                      color: Colors.orange.withOpacity(0.9)),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _BuySheetCol extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _BuySheetCol({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: TextStyle(fontSize: 10.sp, color: Colors.black54)),
      SizedBox(height: 4.h),
      Container(
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: valueColor ?? Colors.black87)),
      ),
    ]);
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
  double quantity;
  int alertAmount;
  String? image;
  bool retail;

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
    this.retail = false,
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
      'retail': retail,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      randomNumber: (map['randomNumber'] ?? 0).toInt(),
      name: map['name'] ?? '',
      sellingPrice1: (map['sellingPrice1'] ?? 0.0).toDouble(),
      sellingPrice2: (map['sellingPrice2'] ?? 0.0).toDouble(),
      sellingPrice3: (map['sellingPrice3'] ?? 0.0).toDouble(),
      costPrice: (map['costPrice'] ?? 0.0).toDouble(),
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      alertAmount: (map['alertAmount'] ?? 0).toInt(),
      image: map['image'],
      retail: map['retail'] == true,
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
