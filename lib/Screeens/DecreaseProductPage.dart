import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'Invoices/All_invoices.dart';
import 'Invoices/InvoiceDetailPage.dart';
import 'Data/DataEntryScreen.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/return_invoice_save_service.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import '../Widgets/egypt_phone_field.dart';
import 'home_page.dart';

class DecreaseProductPage extends StatefulWidget {
  /// When true, saves as [returnInvoices] (stock in, reversed profit/sales/box).
  final bool isReturnInvoice;

  const DecreaseProductPage({super.key, this.isReturnInvoice = false});

  @override
  _DecreaseProductPageState createState() => _DecreaseProductPageState();
}

void _selectAllField(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

class _DecreaseProductPageState extends State<DecreaseProductPage> {
  String get _pageTitle =>
      widget.isReturnInvoice ? 'فواتير المرتجع' : 'المبيعات';

  String get _mainCollection =>
      widget.isReturnInvoice ? 'returnInvoices' : 'invoices';

  String get _clientInvoiceSubcollection =>
      widget.isReturnInvoice ? 'returnInvoices' : 'invoices';

  final List<Product> _products = [];
  DateTime? _selectedDate;

  final List<Map<String, dynamic>> _addedProducts = [];
  final TextEditingController _dateController = TextEditingController();
  bool _dataModified = false;
  bool _isSaving = false;
  bool _isFetching = true;
  double _clientBalance = 0.0;
  TextEditingController _clientNameController = TextEditingController();
  TextEditingController _productController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _newClientNameController = TextEditingController();
  List<String> _clients = [];
  int _defaultPriceTier = 1;
  bool _barcodeExternal = false;
  Map<String, dynamic>? _lastInvoice;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _showClientNameDialog() {
    String searchQuery = '';
    bool showAddField = false;
    String? duplicateWarning;
    final TextEditingController searchCtrl = TextEditingController();
    final TextEditingController newClientCtrl = TextEditingController();
    final TextEditingController newClientBalanceCtrl = TextEditingController();
    final TextEditingController newClientPhoneCtrl = TextEditingController();
    final TextEditingController localPaidCtrl =
        TextEditingController(text: _paidAmountController.text);
    String selectedClient = _clientNameController.text;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final filtered = searchQuery.isEmpty
              ? _clients
              : _clients
                  .where((c) =>
                      c.toLowerCase().contains(searchQuery.toLowerCase()))
                  .toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20.h,
                left: 16.w,
                right: 16.w,
                top: 20.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'اختر العميل',
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),

                  // ── Search + Add button ──
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            hintText: 'ابحث عن عميل...',
                            hintTextDirection: TextDirection.rtl,
                            prefixIcon: const Icon(Icons.search,
                                color: Colors.black54),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: Colors.black54),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      setSheet(() => searchQuery = '');
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
                              setSheet(() => searchQuery = v.trim()),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Tooltip(
                        message: 'إضافة عميل جديد',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10.r),
                          onTap: () =>
                              setSheet(() => showAddField = !showAddField),
                          child: Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: showAddField
                                  ? Colors.black87
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: Icon(
                              Icons.person_add_alt_1,
                              color: showAddField
                                  ? Colors.white
                                  : Colors.black87,
                              size: 22.sp,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Add new client inline field ──
                  if (showAddField) ...[
                    SizedBox(height: 10.h),
                    TextField(
                      controller: newClientCtrl,
                      textDirection: TextDirection.rtl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'اسم العميل الجديد',
                        hintTextDirection: TextDirection.rtl,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: newClientBalanceCtrl,
                      textDirection: TextDirection.rtl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        hintText: 'الرصيد الافتتاحي',
                        hintTextDirection: TextDirection.rtl,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    EgyptPhoneField(
                      controller: newClientPhoneCtrl,
                      hintText: '1xxxxxxxxx',
                    ),
                    SizedBox(height: 8.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r)),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                        onPressed: () async {
                          final newName = newClientCtrl.text.trim();
                          if (newName.isEmpty) return;
                          if (!EgyptPhoneField.isValidLocalPart(
                              newClientPhoneCtrl.text)) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'يرجى إدخال رقم هاتف صحيح بعد +20'),
                              ),
                            );
                            return;
                          }
                          final alreadyExists = _clients
                              .map((c) => c.toLowerCase())
                              .contains(newName.toLowerCase());
                          if (!alreadyExists) {
                            final balance = double.tryParse(
                                    newClientBalanceCtrl.text.trim()) ??
                                0.0;
                            final phone = EgyptPhoneField.toWhatsappDigits(
                                newClientPhoneCtrl.text);
                            await FirebaseFirestore.instance
                                .collection('clients')
                                .doc(newName)
                                .set({
                              'clientName': newName,
                              'balance': balance,
                              'phone': phone,
                              'id': newName,
                            }, SetOptions(merge: true));
                          }
                          if (!ctx.mounted) return;
                          setSheet(() {
                            if (!alreadyExists) {
                              _clients.add(newName);
                              duplicateWarning = null;
                            } else {
                              duplicateWarning = 'هذا العميل موجود بالفعل';
                            }
                            selectedClient = alreadyExists
                                ? _clients.firstWhere((c) =>
                                    c.toLowerCase() == newName.toLowerCase())
                                : newName;
                            if (!alreadyExists) {
                              showAddField = false;
                              newClientCtrl.clear();
                              newClientBalanceCtrl.clear();
                              newClientPhoneCtrl.clear();
                            }
                          });
                        },
                        child: Text('إضافة العميل',
                            style: TextStyle(fontSize: 13.sp)),
                      ),
                    ),
                  ],
                  // ── Duplicate warning ──
                  if (duplicateWarning != null) ...[  
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
                              duplicateWarning!,
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
                  SizedBox(height: 10.h),

                  // ── Client list ──
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.30),
                    child: filtered.isEmpty
                        ? Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            child: Text(
                              'لا يوجد عميل بهذا الاسم',
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final client = filtered[i];
                              final isSelected = client == selectedClient;
                              return InkWell(
                                onTap: () async {
                                  setSheet(() => selectedClient = client);
                                  await _fetchAndSetClientBalance(client);
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12.w, vertical: 10.h),
                                  margin:
                                      EdgeInsets.symmetric(vertical: 3.h),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.grey.shade100,
                                    borderRadius:
                                        BorderRadius.circular(10.r),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 18.sp,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black54,
                                      ),
                                      SizedBox(width: 10.w),
                                      Expanded(
                                        child: Text(
                                          client,
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
                                            size: 18.sp,
                                            color: Colors.orange),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Divider(height: 20.h),

                  // ── المبلغ المدفوع ──
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'المبلغ المدفوع',
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: localPaidCtrl,
                    textDirection: TextDirection.rtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixIcon:
                          const Icon(Icons.payments_outlined, color: Colors.black54),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            const BorderSide(color: Colors.black87, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  SizedBox(height: 14.h),

                  // ── Confirm button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 13.h),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r)),
                      ),
                      onPressed: selectedClient.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _clientNameController.text = selectedClient;
                                _paidAmountController.text =
                                    localPaidCtrl.text;
                              });
                              Navigator.of(ctx).pop();
                            },
                      child: Text('تأكيد',
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          );
        });
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
        double quantity = double.tryParse(product['amount'].toString()) ?? 0.0;
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
      print('the number of the products ' + _products.length.toString());
    } catch (e) {
      print('Error fetching products: $e');
      setState(() {
        _isFetching = false;
      });
    }
  }

  Future<void> _fetchClients() async {
    try {
      QuerySnapshot querySnapshot =
      await FirebaseFirestore.instance.collection('clients').get();
      setState(() {
        _clients = querySnapshot.docs
            .map((doc) => doc['clientName'] as String)
            .toList();
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

  void _saveData({
    String? clientName,
    double? paidAmount,
    String paymentMethod = 'نقداً',
    String notes = '',
    double invoiceDiscount = 0.0,
    bool discountIsPercent = true,
  }) async {
    final String effectiveClient =
        (clientName ?? _clientNameController.text).trim();
    final double effectivePaid =
        paidAmount ?? (double.tryParse(_paidAmountController.text) ?? 0.0);

    if (effectiveClient.isEmpty) {
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
      if (widget.isReturnInvoice) {
        _lastInvoice = await ReturnInvoiceSaveService.save(
          clientName: effectiveClient,
          selectedDate: _selectedDate,
          products: List<Map<String, dynamic>>.from(_addedProducts),
          paidAmount: effectivePaid,
          paymentMethod: paymentMethod,
          notes: notes,
          invoiceDiscount: invoiceDiscount,
          discountIsPercent: discountIsPercent,
          previousBalanceSnapshot: _clientBalance,
          totalSumBeforeDiscount: _calculateTotalSum(),
          calculateTotalCost: (_) => _calculateTotalCost(),
        );
      } else {
        final invoiceQuery = await FirebaseFirestore.instance
            .collection(_mainCollection)
            .orderBy('invoiceNumber', descending: true)
            .limit(1)
            .get();

        var newInvoiceNumber = 1;
        if (invoiceQuery.docs.isNotEmpty) {
          newInvoiceNumber =
              (invoiceQuery.docs.first['invoiceNumber'] as num).toInt() + 1;
        }

        final totalCost = await _calculateTotalCost();
        final totalSum = _calculateTotalSum();
        final effectiveDiscountAmt = discountIsPercent
            ? totalSum * invoiceDiscount / 100
            : invoiceDiscount;
        final totalSumFinal = totalSum - effectiveDiscountAmt;
        final profitMargin = totalSumFinal - totalCost;
        final balance = totalSumFinal - effectivePaid;

        final existingBalance = await _fetchClientBalance(effectiveClient);
        final updatedBalance = existingBalance + balance;

        final invoiceData = <String, dynamic>{
          'invoiceNumber': newInvoiceNumber,
          'clientName': effectiveClient,
          'date': _selectedDate,
          'totalSum': totalSumFinal,
          'profitMargin': profitMargin,
          'paidAmount': effectivePaid,
          'balance': balance,
          'previousBalance': _clientBalance,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'invoiceDiscount': effectiveDiscountAmt,
          'invoiceType': 'sale',
          'products': _addedProducts,
        };

        final docRef = await FirebaseFirestore.instance
            .collection(_mainCollection)
            .add(invoiceData);

        await docRef.update({'id': docRef.id});
        _lastInvoice = {...invoiceData, 'id': docRef.id};

        for (final product in _addedProducts) {
          final query = await FirebaseFirestore.instance
              .collection('products')
              .where('name', isEqualTo: product['product'])
              .get();

          if (query.docs.isNotEmpty) {
            for (final doc in query.docs) {
              final existingAmount = (doc['quantity'] as num).toDouble();
              final decrementAmount =
                  double.tryParse(product['amount'].toString()) ?? 0.0;
              final newAmount = existingAmount - decrementAmount;

              await FirebaseFirestore.instance
                  .collection('products')
                  .doc(doc.id)
                  .update({'quantity': newAmount});

              await FirebaseFirestore.instance
                  .collection('products')
                  .doc(doc.id)
                  .collection('changes')
                  .add({
                'date': product['date'],
                'amount': decrementAmount,
                'type': 'decrease',
              });
            }
          }
        }

        final clientDocRef = FirebaseFirestore.instance
            .collection('clients')
            .doc(effectiveClient);

        await clientDocRef.set({
          'clientName': effectiveClient,
          'balance': updatedBalance,
        }, SetOptions(merge: true));

        await clientDocRef.collection(_clientInvoiceSubcollection).add({
          'invoiceId': docRef.id,
          'invoiceNumber': newInvoiceNumber,
          'date': _selectedDate,
          'totalSum': totalSumFinal,
          'paidAmount': effectivePaid,
          'balance': balance,
          'previousBalance': _clientBalance,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'products': _addedProducts,
        });

        await clientDocRef.collection('balanceHistory').add({
          'enteredBalance': effectivePaid,
          'balanceBefore': existingBalance,
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'sale',
        });

        final boxDocRef =
            FirebaseFirestore.instance.collection('box').doc('mainBox');

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final boxSnapshot = await transaction.get(boxDocRef);

          if (boxSnapshot.exists) {
            final currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
            transaction.update(
                boxDocRef, {'value': currentBoxValue + effectivePaid});
          } else {
            transaction.set(boxDocRef, {'value': effectivePaid});
          }

          await boxDocRef.collection('changes').add({
            'date': FieldValue.serverTimestamp(),
            'value': effectivePaid,
            'type': 'addition',
            'name': effectiveClient,
            'invoiceNumber': newInvoiceNumber,
          });
        });
      }

      setState(() {
        _dataModified = false;
        _isSaving = false;
      });

      if (!mounted) return;
      _showSaveSuccessDialog(_lastInvoice!);
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving data: $e')),
      );
    }
  }

  void _navigateHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  void _showSaveSuccessDialog(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          title: Text(
            'تم الحفظ بنجاح',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInvoiceSuccessContent(invoice),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final clientName =
                          invoice['clientName']?.toString() ?? '';
                      InvoicePrintUi.printInvoice(
                        ctx,
                        invoice,
                        clientId: clientName.isNotEmpty
                            ? clientName
                            : null,
                      );
                    },
                    icon: const Icon(Icons.print, color: Colors.white),
                    label: const Text('طباعة الفاتورة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final clientName =
                          invoice['clientName']?.toString() ?? '';
                      InvoicePrintUi.previewInvoice(
                        ctx,
                        invoice,
                        clientId: clientName.isNotEmpty
                            ? clientName
                            : null,
                      );
                    },
                    icon: Icon(Icons.receipt_long,
                        color: Colors.deepPurple.shade700),
                    label: const Text('معاينة الطباعة (مؤقت)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple.shade700,
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      WhatsappInvoiceShareService.showShareOptions(
                        ctx,
                        invoice: invoice,
                        onShareSuccess: () {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('تم فتح واتساب'),
                            ),
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.chat, color: Colors.white),
                    label: const Text('مشاركة في واتساب'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _navigateHome();
                    },
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('إنهاء'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceSuccessContent(Map<String, dynamic> invoice) {
    final date = invoice['date'];
    String dateStr = '';
    if (date is Timestamp) {
      final d = date.toDate().toLocal();
      dateStr = '${d.day}/${d.month}/${d.year}';
    } else if (date is DateTime) {
      final d = date.toLocal();
      dateStr = '${d.day}/${d.month}/${d.year}';
    }

    Widget line(String label, String value) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(fontSize: 13.sp, color: Colors.black54),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        line('رقم الفاتورة', '#${invoice['invoiceNumber']}'),
        line('العميل', invoice['clientName']?.toString() ?? ''),
        if (dateStr.isNotEmpty) line('التاريخ', dateStr),
        line('طريقة الدفع', invoice['paymentMethod']?.toString() ?? ''),
      ],
    );
  }

  Future<void> _fetchAndSetClientBalance(String clientName) async {
    DocumentSnapshot clientDoc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientName)
        .get();

    if (clientDoc.exists) {
      setState(() {
        _clientBalance = (clientDoc['balance'] ?? 0.0).toDouble();
      });
    } else {
      setState(() {
        _clientBalance = 0.0;
      });
    }
  }

  // ─────────────────────────────────────────────
  // Product bottom sheet  (add or edit)
  // ─────────────────────────────────────────────
  double _lineTotalForEntry(Map<String, dynamic> entry, double amount) {
    final price = (entry['selectedPrice'] as num).toDouble();
    final discount = (entry['discount'] ?? 0.0).toDouble();
    final isPercent = entry['discountIsPercent'] == true;
    final subtotal = price * amount;
    final result =
        isPercent ? subtotal - (subtotal * discount / 100) : subtotal - discount;
    return result < 0 ? 0 : result;
  }

  void _incrementInvoiceLineQuantity(int index) {
    setState(() {
      final p = Map<String, dynamic>.from(_addedProducts[index]);
      final currentAmount = double.tryParse(p['amount'].toString()) ?? 0.0;
      final newAmount = currentAmount + 1;
      p['amount'] = newAmount.toStringAsFixed(2);
      p['total'] = _lineTotalForEntry(p, newAmount);
      _addedProducts[index] = p;
      _dataModified = true;
    });
  }

  void _showProductSheet({int? editIndex, Product? newProduct}) {
    final Product product = editIndex != null
        ? (_products.firstWhere(
            (p) => p.name == _addedProducts[editIndex]['product'],
            orElse: () => newProduct!))
        : newProduct!;

    double amount = editIndex != null
        ? double.tryParse(_addedProducts[editIndex]['amount'].toString()) ?? 1.0
        : 1.0;
    int priceTier =
        editIndex != null ? (_addedProducts[editIndex]['priceTier'] ?? 1) : _defaultPriceTier;
    double customPrice = editIndex != null && (_addedProducts[editIndex]['priceTier'] ?? 1) == 0
        ? ((_addedProducts[editIndex]['selectedPrice'] ?? 0.0) as num).toDouble()
        : 0.0;
    double discount = editIndex != null
        ? ((_addedProducts[editIndex]['discount'] ?? 0.0) as num).toDouble()
        : 0.0;
    bool discountIsPercent = editIndex != null
        ? (_addedProducts[editIndex]['discountIsPercent'] ?? true)
        : true;
    String barcodeNote =
        editIndex != null ? (_addedProducts[editIndex]['barcodeNote'] ?? '') : '';
    bool removeProduct = false;
    bool costObscured = false;

    final TextEditingController qtyCtrl =
        TextEditingController(text: amount.toStringAsFixed(1));
    final TextEditingController discountCtrl =
        TextEditingController(text: discount > 0 ? discount.toStringAsFixed(1) : '');
    final TextEditingController barcodeCtrl =
        TextEditingController(text: barcodeNote);
    final TextEditingController customPriceCtrl =
        TextEditingController(text: customPrice > 0 ? customPrice.toStringAsFixed(2) : '');

    double getPriceForTier(int tier) {
      if (tier == 0) return customPrice;
      switch (tier) {
        case 2:
          return product.sellingPrice2;
        case 3:
          return product.sellingPrice3;
        default:
          return product.sellingPrice1;
      }
    }

    double calcTotal(double amt, double disc, bool isPercent, int tier) {
      double price = getPriceForTier(tier);
      double subtotal = price * amt;
      double result =
          isPercent ? subtotal - (subtotal * disc / 100) : subtotal - disc;
      return result < 0 ? 0 : result;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
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
                    // Product name
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(product.name,
                          style: TextStyle(
                              fontSize: 17.sp, fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: 14.h),

                    // ── سعر البيع ──
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: _SheetValueBox(
                              value: getPriceForTier(priceTier).toStringAsFixed(1))),
                      SizedBox(width: 8.w),
                      _PriceTierBtn(
                          label: '3',
                          selected: priceTier == 3,
                          onTap: () => setSheet(() => priceTier = 3)),
                      SizedBox(width: 4.w),
                      _PriceTierBtn(
                          label: '2',
                          selected: priceTier == 2,
                          onTap: () => setSheet(() => priceTier = 2)),
                      SizedBox(width: 4.w),
                      _PriceTierBtn(
                          label: '1',
                          selected: priceTier == 1,
                          onTap: () => setSheet(() => priceTier = 1)),
                      SizedBox(width: 4.w),
                      _PriceTierBtn(
                          label: 'خ',
                          selected: priceTier == 0,
                          onTap: () => setSheet(() => priceTier = 0)),
                      SizedBox(width: 8.w),
                      Text('سعر البيع', style: TextStyle(fontSize: 13.sp)),
                    ]),
                    // ── Custom price input (visible when خاص selected) ──
                    if (priceTier == 0) ...[  
                      SizedBox(height: 8.h),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: customPriceCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            autofocus: true,
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800),
                            decoration: InputDecoration(
                              hintText: 'أدخل السعر الخاص',
                              hintStyle: TextStyle(fontSize: 12.sp, color: Colors.grey),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.r),
                                  borderSide: const BorderSide(color: Colors.orange)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.r),
                                  borderSide: const BorderSide(color: Colors.orange, width: 2)),
                              contentPadding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                              prefixIcon: Icon(Icons.edit, size: 18.sp, color: Colors.orange),
                            ),
                            onTap: () => _selectAllField(customPriceCtrl),
                            onChanged: (v) => setSheet(() {
                              customPrice = double.tryParse(v) ?? 0.0;
                            }),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text('سعر خاص', style: TextStyle(fontSize: 13.sp)),
                      ]),
                    ],
                    SizedBox(height: 10.h),

                    // ── الكمية ──
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: _SheetValueBox(
                              value: calcTotal(
                                      amount, discount, discountIsPercent, priceTier)
                                  .toStringAsFixed(1))),
                      SizedBox(width: 8.w),
                      _CircleBtn(
                          icon: Icons.remove,
                          onTap: () {
                            if (amount > 1) {
                              setSheet(() {
                                amount -= 1;
                                qtyCtrl.text = amount.toStringAsFixed(1);
                              });
                            }
                          }),
                      SizedBox(width: 6.w),
                      SizedBox(
                        width: 64.w,
                        child: TextField(
                          controller: qtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide:
                                    const BorderSide(color: Colors.orange)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(
                                    color: Colors.orange, width: 2)),
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8.h),
                          ),
                          onTap: () => _selectAllField(qtyCtrl),
                          onChanged: (v) =>
                              setSheet(() => amount = double.tryParse(v) ?? amount),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      _CircleBtn(
                          icon: Icons.add,
                          onTap: () => setSheet(() {
                                amount += 1;
                                qtyCtrl.text = amount.toStringAsFixed(1);
                              })),
                      SizedBox(width: 8.w),
                      Text('الكمية', style: TextStyle(fontSize: 13.sp)),
                    ]),
                    SizedBox(height: 10.h),

                    // ── الخصم ──
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: _SheetValueBox(
                              value: (discountIsPercent
                                      ? getPriceForTier(priceTier) *
                                          amount *
                                          discount /
                                          100
                                      : discount)
                                  .toStringAsFixed(1))),
                      SizedBox(width: 8.w),
                      GestureDetector(
                        onTap: () => setSheet(() => discountIsPercent = true),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 9.h),
                          decoration: BoxDecoration(
                            color: discountIsPercent
                                ? Colors.orange.withOpacity(0.85)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text('%',
                              style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                  color: discountIsPercent
                                      ? Colors.white
                                      : Colors.black87)),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      SizedBox(
                        width: 74.w,
                        child: TextField(
                          controller: discountCtrl,
                          textAlign: TextAlign.center,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(fontSize: 14.sp),
                          decoration: InputDecoration(
                            hintText: 'نسبه',
                            hintStyle:
                                TextStyle(fontSize: 12.sp, color: Colors.grey),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8.h, horizontal: 6.w),
                          ),
                          onTap: () => _selectAllField(discountCtrl),
                          onChanged: (v) =>
                              setSheet(() => discount = double.tryParse(v) ?? 0.0),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      GestureDetector(
                        onTap: () => setSheet(() => discountIsPercent = false),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 9.h),
                          decoration: BoxDecoration(
                            color: !discountIsPercent
                                ? Colors.orange.withOpacity(0.85)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Icon(Icons.monetization_on_outlined,
                              size: 16.sp,
                              color: !discountIsPercent
                                  ? Colors.white
                                  : Colors.black87),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text('الخصم', style: TextStyle(fontSize: 13.sp)),
                    ]),
                    SizedBox(height: 12.h),

                    // ── ملاحظة للمنتج ──
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('ملاحظه للمنتج تظهر في الفاتورة',
                          style:
                              TextStyle(fontSize: 11.sp, color: Colors.black54)),
                    ),
                    SizedBox(height: 6.h),
                    Row(children: [
                      Icon(Icons.qr_code, size: 38.sp, color: Colors.black87),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            hintText: 'مثلا:اللون | الرقم التسلسلي |الحجم',
                            hintStyle: TextStyle(fontSize: 11.sp),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8.h, horizontal: 12.w),
                            suffixIcon:
                                Icon(Icons.edit_outlined, size: 18.sp),
                          ),
                          onTap: () => _selectAllField(barcodeCtrl),
                          onChanged: (v) => barcodeNote = v,
                        ),
                      ),
                    ]),
                    SizedBox(height: 12.h),

                    // ── الكمية المتوفرة + التكلفة ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الكميه المتوفره',
                            style: TextStyle(fontSize: 13.sp)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                product.quantity.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: 6.h),
                            GestureDetector(
                              onTap: () => setSheet(
                                  () => costObscured = !costObscured),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 24.w, vertical: 8.h),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6.r),
                                  child: costObscured
                                      ? ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                              sigmaX: 8, sigmaY: 8),
                                          child: Text(
                                            product.costPrice
                                                .toStringAsFixed(2),
                                            style: TextStyle(
                                              fontSize: 15.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          product.costPrice
                                              .toStringAsFixed(2),
                                          style: TextStyle(
                                            fontSize: 15.sp,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),

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
                          onPressed: () {
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
                            double price = getPriceForTier(priceTier);
                            double total = calcTotal(
                                amount, discount, discountIsPercent, priceTier);
                            final entry = {
                              'product': product.name,
                              'date': _selectedDate,
                              'amount': amount.toStringAsFixed(2),
                              'sellingPrice1': product.sellingPrice1,
                              'sellingPrice2': product.sellingPrice2,
                              'sellingPrice3': product.sellingPrice3,
                              'quantity': product.quantity,
                              'selectedPrice': priceTier == 0 ? customPrice : price,
                              'priceTier': priceTier,
                              'total': total,
                              'discount': discount,
                              'discountIsPercent': discountIsPercent,
                              'barcodeNote': barcodeNote,
                            };
                            setState(() {
                              if (editIndex != null) {
                                _addedProducts[editIndex] = entry;
                              } else {
                                int idx = _addedProducts.indexWhere(
                                    (p) => p['product'] == product.name);
                                if (idx != -1) {
                                  _addedProducts[idx] = entry;
                                } else {
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
  // Checkout sheet  (حاسب)
  // ─────────────────────────────────────────────
  void _showCheckoutSheet() {
    if (_addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إضافة منتجات إلى الفاتورة')));
      return;
    }

    String paymentMethod = 'نقداً';
    double invoiceDiscount = 0.0;
    bool discountIsPercent = true;
    String checkoutClient = _clientNameController.text;
    String notes = '';

    final TextEditingController paidCtrl = TextEditingController(
      text: _calculateTotalSum().toStringAsFixed(2),
    );
    final TextEditingController discountCtrl = TextEditingController();
    final TextEditingController notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          double totalSum = _calculateTotalSum();
          double effectiveDiscountAmt = discountIsPercent
              ? totalSum * invoiceDiscount / 100
              : invoiceDiscount;
          double totalAfterDiscount = totalSum - effectiveDiscountAmt;
          double paid = double.tryParse(paidCtrl.text) ?? 0.0;
          double remaining = paid - totalAfterDiscount;
          final bool isCash = paymentMethod == 'نقداً';
          final bool paidLessThanTotal =
              isCash && paid + 0.001 < totalAfterDiscount;

          void syncPaidForPaymentMethod() {
            if (paymentMethod == 'نقداً') {
              final sum = _calculateTotalSum();
              final disc = discountIsPercent
                  ? sum * invoiceDiscount / 100
                  : invoiceDiscount;
              paidCtrl.text = (sum - disc).toStringAsFixed(2);
            } else if (paymentMethod == 'آجل') {
              paidCtrl.clear();
            }
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
                    // ── طريقة الدفع ──
                    Row(
                      children: [
                        Text('طريقة الدفع',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        ...['نقداً', 'آجل', 'بطاقه', 'ش'].map((m) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Radio<String>(
                                  value: m,
                                  groupValue: paymentMethod,
                                  activeColor: Colors.green,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => setSheet(() {
                                    paymentMethod = v!;
                                    syncPaidForPaymentMethod();
                                  }),
                                ),
                                Text(m,
                                    style: TextStyle(fontSize: 11.sp)),
                              ],
                            )),
                      ],
                    ),
                    SizedBox(height: 10.h),

                    // ── الإجمالي ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الإجمالي',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: 12.w),
                            padding: EdgeInsets.symmetric(
                                vertical: 10.h, horizontal: 12.w),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              totalAfterDiscount.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),

                    // ── المدفوع ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المدفوع',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold)),
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
                                      borderRadius:
                                          BorderRadius.circular(8.r)),
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 8.w),
                                  suffixIcon: isCash && paid == 0
                                      ? Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.red,
                                          size: 20.sp)
                                      : null,
                                ),
                                onTap: () => _selectAllField(paidCtrl),
                                onChanged: (_) => setSheet(() {}),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                    if (paidLessThanTotal)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h),
                        child: Text(
                          'المبلغ المدفوع أصغر من الإجمالي',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SizedBox(height: 8.h),

                    // ── الخصم + الباقي ──
                    Row(children: [
                      // Remaining
                      Expanded(
                        child: Container(
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
                          child: Text(
                            remaining.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: remaining >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700),
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Text('الباقي',
                          style: TextStyle(fontSize: 12.sp)),
                      SizedBox(width: 6.w),
                      // % toggle
                      GestureDetector(
                        onTap: () => setSheet(() {
                          discountIsPercent = !discountIsPercent;
                          syncPaidForPaymentMethod();
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
                      SizedBox(width: 6.w),
                      SizedBox(
                        width: 80.w,
                        child: TextField(
                          controller: discountCtrl,
                          textAlign: TextAlign.center,
                          keyboardType:
                              const TextInputType.numberWithOptions(
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
                            syncPaidForPaymentMethod();
                          }),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text('الخصم',
                          style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold)),
                    ]),
                    SizedBox(height: 14.h),

                    // ── حفظ الفاتورة لحساب عميل ──
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('حفظ الفاتورة لحساب عميل',
                          style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(height: 8.h),
                    Row(children: [
                      Icon(Icons.barcode_reader,
                          size: 38.sp, color: Colors.black87),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(
                              text: checkoutClient),
                          optionsBuilder: (val) {
                            if (val.text.isEmpty)
                              return const Iterable<String>.empty();
                            return _clients.where((c) => c
                                .toLowerCase()
                                .contains(val.text.toLowerCase()));
                          },
                          fieldViewBuilder:
                              (ctx2, ctrl2, focus, onSubmit) {
                            return TextField(
                              controller: ctrl2,
                              focusNode: focus,
                              textAlign: TextAlign.right,
                              onTap: () => _selectAllField(ctrl2),
                              onChanged: (v) {
                                checkoutClient = v;
                                setSheet(() {});
                              },
                              decoration: InputDecoration(
                                hintText:
                                    'ابحث عن عميل أو اكتب اسم',
                                hintStyle:
                                    TextStyle(fontSize: 12.sp),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8.r)),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 10.h, horizontal: 12.w),
                                suffixIcon: checkoutClient.isEmpty
                                    ? Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.red,
                                        size: 20.sp)
                                    : null,
                              ),
                            );
                          },
                          onSelected: (c) =>
                              setSheet(() => checkoutClient = c),
                        ),
                      ),
                    ]),
                    SizedBox(height: 10.h),

                    // ── ملاحظات ──
                    TextField(
                      controller: notesCtrl,
                      textAlign: TextAlign.right,
                      onTap: () => _selectAllField(notesCtrl),
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

                    // ── Buttons ──
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
                            backgroundColor:
                                Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8.r)),
                            padding:
                                EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          onPressed: () async {
                            if (checkoutClient.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('يجب ادخال اسم العميل')));
                              return;
                            }
                            final paidAmount =
                                double.tryParse(paidCtrl.text) ?? 0.0;
                            if (paymentMethod == 'نقداً' &&
                                paidAmount + 0.001 < totalAfterDiscount) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'المبلغ المدفوع أصغر من الإجمالي'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            await _fetchAndSetClientBalance(
                                checkoutClient.trim());
                            _clientNameController.text =
                                checkoutClient.trim();
                            _saveData(
                              clientName: checkoutClient.trim(),
                              paidAmount: paidAmount,
                              paymentMethod: paymentMethod,
                              notes: notes,
                              invoiceDiscount: invoiceDiscount,
                              discountIsPercent: discountIsPercent,
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

  // ─────────────────────────────────────────────
  // Drawer methods
  // ─────────────────────────────────────────────

  void _showCalculatorDialog() {
    String _expr = '';
    String _display = '0';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setCalc) {
          void _press(String val) {
            setCalc(() {
              if (val == 'C') {
                _expr = '';
                _display = '0';
              } else if (val == '=') {
                try {
                  // Simple evaluator via Dart double arithmetic
                  final result = _evalExpr(_expr);
                  _display = result.toStringAsFixed(2)
                      .replaceAll(RegExp(r'\.?0+$'), '');
                  _expr = _display;
                } catch (_) {
                  _display = 'خطأ';
                  _expr = '';
                }
              } else if (val == '⌫') {
                if (_expr.isNotEmpty) {
                  _expr = _expr.substring(0, _expr.length - 1);
                  _display = _expr.isEmpty ? '0' : _expr;
                }
              } else {
                _expr += val;
                _display = _expr;
              }
            });
          }

          Widget _btn(String label,
              {Color bg = const Color(0xfff0f0f0), Color fg = Colors.black87}) {
            return Expanded(
              child: GestureDetector(
                onTap: () => _press(label),
                child: Container(
                  margin: EdgeInsets.all(3.w),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Center(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: fg)),
                  ),
                ),
              ),
            );
          }

          return Directionality(
            textDirection: TextDirection.ltr,
            child: AlertDialog(
              title: Text('الحاسبة',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 16.sp, fontWeight: FontWeight.bold)),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              content: SizedBox(
                width: 280.w,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                        horizontal: 12.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(_display,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 26.sp, fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(height: 10.h),
                  Row(children: [
                    _btn('7'),
                    _btn('8'),
                    _btn('9'),
                    _btn('÷',
                        bg: Colors.orange.shade100,
                        fg: Colors.orange.shade800),
                  ]),
                  Row(children: [
                    _btn('4'),
                    _btn('5'),
                    _btn('6'),
                    _btn('×',
                        bg: Colors.orange.shade100,
                        fg: Colors.orange.shade800),
                  ]),
                  Row(children: [
                    _btn('1'),
                    _btn('2'),
                    _btn('3'),
                    _btn('-',
                        bg: Colors.orange.shade100,
                        fg: Colors.orange.shade800),
                  ]),
                  Row(children: [
                    _btn('0'),
                    _btn('.'),
                    _btn('⌫', bg: Colors.red.shade50, fg: Colors.red),
                    _btn('+',
                        bg: Colors.orange.shade100,
                        fg: Colors.orange.shade800),
                  ]),
                  Row(children: [
                    _btn('C',
                        bg: Colors.grey.shade300, fg: Colors.black87),
                    _btn('=',
                        bg: Colors.orange.withOpacity(0.85),
                        fg: Colors.white),
                  ]),
                ]),
              ),
            ),
          );
        });
      },
    );
  }

  double _evalExpr(String expr) {
    // Replace display symbols
    expr = expr.replaceAll('×', '*').replaceAll('÷', '/');
    // Split into tokens
    final List<String> tokens = [];
    String num = '';
    for (int i = 0; i < expr.length; i++) {
      final c = expr[i];
      if ('+-*/'.contains(c)) {
        if (num.isNotEmpty) {
          tokens.add(num);
          num = '';
        }
        tokens.add(c);
      } else {
        num += c;
      }
    }
    if (num.isNotEmpty) tokens.add(num);

    // Evaluate * and / first
    List<String> t = List.from(tokens);
    for (int i = 1; i < t.length - 1; i += 2) {
      if (t[i] == '*' || t[i] == '/') {
        double a = double.parse(t[i - 1]);
        double b = double.parse(t[i + 1]);
        double r = t[i] == '*' ? a * b : a / b;
        t.replaceRange(i - 1, i + 2, [r.toString()]);
        i -= 2;
      }
    }
    // Then + and -
    double result = double.parse(t[0]);
    for (int i = 1; i < t.length - 1; i += 2) {
      double b = double.parse(t[i + 1]);
      if (t[i] == '+') result += b;
      if (t[i] == '-') result -= b;
    }
    return result;
  }

  void _queryClientBalanceDialog() {
    String? _selectedClient;
    double? _balance;
    bool _loading = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setQ) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('الاستعلام عن رصيد العميل',
                  style: TextStyle(
                      fontSize: 16.sp, fontWeight: FontWeight.bold)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  decoration:
                      InputDecoration(hintText: 'اختر اسم العميل'),
                  items: _clients
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) async {
                    setQ(() {
                      _selectedClient = val;
                      _balance = null;
                      _loading = true;
                    });
                    final doc = await FirebaseFirestore.instance
                        .collection('clients')
                        .doc(val)
                        .get();
                    setQ(() {
                      _balance = doc.exists
                          ? (doc['balance'] ?? 0.0).toDouble()
                          : 0.0;
                      _loading = false;
                    });
                  },
                ),
                SizedBox(height: 16.h),
                if (_loading)
                  const CircularProgressIndicator()
                else if (_balance != null)
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: _balance! > 0
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                          color: _balance! > 0
                              ? Colors.red.shade200
                              : Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المتبقي:',
                            style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold)),
                        Text('${_balance!.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: _balance! > 0
                                    ? Colors.red.shade700
                                    : Colors.green.shade700)),
                      ],
                    ),
                  ),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إغلاق',
                        style: TextStyle(color: Colors.orange))),
              ],
            ),
          );
        });
      },
    );
  }

  void _confirmClearProducts() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('مسح القائمة',
              style:
                  TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          content: Text('هل تريد مسح جميع المنتجات من القائمة الحالية؟',
              style: TextStyle(fontSize: 14.sp)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('إلغاء', style: TextStyle(color: Colors.orange)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _addedProducts.clear();
                  _clientNameController.clear();
                  _paidAmountController.clear();
                  _clientBalance = 0.0;
                  _dataModified = false;
                });
              },
              child: Text('مسح', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final items = [
      _DrawerItem(
        icon: Icons.print_outlined,
        label: 'اعاده طباعه الفاتورة',
        onTap: () {
          Navigator.pop(context);
          if (_lastInvoice != null) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        InvoiceDetailPage(invoice: _lastInvoice!)));
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InvoiceListPage(
                  collection: _mainCollection,
                  pageTitle: widget.isReturnInvoice
                      ? 'فواتير المرتجع'
                      : 'فواتير المبيعات',
                ),
              ),
            );
          }
        },
      ),
      _DrawerItem(
        icon: Icons.edit_document,
        label: widget.isReturnInvoice
            ? 'تعديل فاتورة مرتجع'
            : 'تعديل فاتورة البيع',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceListPage(
                collection: _mainCollection,
                pageTitle: widget.isReturnInvoice
                    ? 'فواتير المرتجع'
                    : 'فواتير المبيعات',
              ),
            ),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.looks_one_outlined,
        label: 'تثبيت سعر البيع 1',
        isActive: _defaultPriceTier == 1,
        onTap: () {
          Navigator.pop(context);
          setState(() => _defaultPriceTier = 1);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تثبيت سعر البيع 1 للمنتجات الجديدة')));
        },
      ),
      _DrawerItem(
        icon: Icons.looks_two_outlined,
        label: 'تثبيت سعر البيع 2',
        isActive: _defaultPriceTier == 2,
        onTap: () {
          Navigator.pop(context);
          setState(() => _defaultPriceTier = 2);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تثبيت سعر البيع 2 للمنتجات الجديدة')));
        },
      ),
      _DrawerItem(
        icon: Icons.looks_3_outlined,
        label: 'تثبيت سعر البيع 3',
        isActive: _defaultPriceTier == 3,
        onTap: () {
          Navigator.pop(context);
          setState(() => _defaultPriceTier = 3);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تثبيت سعر البيع 3 للمنتجات الجديدة')));
        },
      ),
      _DrawerItem(
        icon: Icons.calculate_outlined,
        label: 'الحاسبة',
        onTap: () {
          Navigator.pop(context);
          _showCalculatorDialog();
        },
      ),
      _DrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'الاستعلام عن الباقي عند العميل',
        onTap: () {
          Navigator.pop(context);
          _queryClientBalanceDialog();
        },
      ),
      _DrawerItem(
        icon: Icons.file_download_outlined,
        label: 'استيراد البيانات من عرض سعر',
        onTap: () {
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('قريبًا',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.bold)),
                content: Text(
                    'ميزة استيراد عروض الأسعار ستكون متاحة قريبًا.',
                    style: TextStyle(fontSize: 14.sp)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('حسنًا',
                          style: TextStyle(color: Colors.orange))),
                ],
              ),
            ),
          );
        },
      ),
      _DrawerItem(
        icon: _barcodeExternal
            ? Icons.qr_code_scanner
            : Icons.document_scanner_outlined,
        label: _barcodeExternal
            ? 'قاريء الباركود: خارج الشاشة'
            : 'قاريء الباركود: متضمن',
        isActive: _barcodeExternal,
        onTap: () {
          Navigator.pop(context);
          setState(() => _barcodeExternal = !_barcodeExternal);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_barcodeExternal
                  ? 'قاريء الباركود: خارج الشاشة'
                  : 'قاريء الباركود: متضمن')));
        },
      ),
      _DrawerItem(
        icon: Icons.add_box_outlined,
        label: 'اضافة منتج جديد',
        onTap: () async {
          Navigator.pop(context);
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DataEntryScreen()));
          await _fetchProducts();
        },
      ),
      _DrawerItem(
        icon: Icons.receipt_long_outlined,
        label: widget.isReturnInvoice ? 'عرض فواتير المرتجع' : 'عرض الفواتير',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceListPage(
                collection: _mainCollection,
                pageTitle: widget.isReturnInvoice
                    ? 'فواتير المرتجع'
                    : 'فواتير المبيعات',
              ),
            ),
          );
        },
      ),
      _DrawerItem(
        icon: Icons.delete_sweep_outlined,
        label: 'مسح المنتجات من القائمة',
        isDestructive: true,
        onTap: () {
          Navigator.pop(context);
          _confirmClearProducts();
        },
      ),
    ];

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
            child: Text(_pageTitle,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              children: items
                  .map((item) => ListTile(
                        leading: Icon(item.icon,
                            color: item.isDestructive
                                ? Colors.red
                                : item.isActive
                                    ? Colors.orange
                                    : Colors.black87,
                            size: 22.sp),
                        title: Text(item.label,
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: item.isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: item.isDestructive
                                    ? Colors.red
                                    : item.isActive
                                        ? Colors.orange.shade800
                                        : Colors.black87)),
                        onTap: item.onTap,
                        dense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 2.h),
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    double totalSum = _calculateTotalSum();
    double totalQty = _addedProducts.fold(
        0.0, (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0.0));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xffeeeced),
        drawer: _buildDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(_pageTitle,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold)),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: Icon(Icons.calendar_today_outlined,
                  color: Colors.white, size: 22.sp),
              tooltip: _dateController.text,
              onPressed: _pickDate,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // ── Search row ──
                Container(
                  color: Colors.white,
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.person_outline,
                          color: Colors.black87, size: 26.sp),
                      onPressed: _showClientNameDialog,
                      tooltip: 'اختر العميل',
                    ),
                    Expanded(
                      child: Container(
                        height: 42.h,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.grey.shade300),
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
                                  return _products.where((p) => p.name
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
                                          'ابحث عن منتج أو استخدام الكاميرا',
                                      hintStyle: TextStyle(
                                          fontSize: 12.sp,
                                          color: Colors.grey),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10.w, vertical: 11.h),
                                      prefixIcon: Icon(Icons.search,
                                          size: 18.sp, color: Colors.grey),
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

                // ── Client badge ──
                if (_clientNameController.text.isNotEmpty)
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 12.w, vertical: 5.h),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () =>
                            setState(() => _clientNameController.clear()),
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
                      if (_clientBalance > 0) ...[
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.red, size: 18.sp),
                        SizedBox(width: 4.w),
                      ],
                      Expanded(
                        child: Text(_clientNameController.text,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold)),
                      ),
                      if (_clientBalance > 0)
                        Text(
                          'رصيد: ${_clientBalance.toStringAsFixed(2)} ج.م',
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
                        child: Text('السعر',
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
                      : ListView.builder(
                          padding:
                              EdgeInsets.only(top: 4.h, bottom: 80.h),
                          itemCount: _addedProducts.length,
                          itemBuilder: (context, index) {
                            final p = _addedProducts[index];
                            final amount =
                                double.tryParse(p['amount'].toString()) ??
                                    0.0;
                            final total =
                                (p['total'] as num).toDouble();
                            final price =
                                (p['selectedPrice'] as num).toDouble();
                            final hasDiscount =
                                (p['discount'] ?? 0.0) > 0;
                            final barcode = p['barcodeNote'] ?? '';

                            return GestureDetector(
                              onTap: () =>
                                  _showProductSheet(editIndex: index),
                              onLongPress: () {
                                final name = p['product']?.toString() ?? '';
                                setState(() {
                                  _addedProducts.removeAt(index);
                                  _dataModified = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      name.isEmpty
                                          ? 'تم حذف المنتج من الفاتورة'
                                          : 'تم حذف $name من الفاتورة',
                                    ),
                                  ),
                                );
                              },
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
                                  Container(
                                    width: 28.w,
                                    alignment: Alignment.center,
                                    child: Icon(Icons.drag_handle,
                                        color: Colors.grey.shade400,
                                        size: 20.sp),
                                  ),
                                  Expanded(
                                      flex: 3,
                                      child: Column(children: [
                                        Text(total.toStringAsFixed(1),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.bold,
                                                color: hasDiscount
                                                    ? Colors
                                                        .orange.shade700
                                                    : Colors.black87)),
                                        if (hasDiscount)
                                          Text(
                                            '- ${p['discount']}${p['discountIsPercent'] == true ? '%' : ' ج.م'}',
                                            style: TextStyle(
                                                fontSize: 10.sp,
                                                color: Colors
                                                    .orange.shade600),
                                          ),
                                      ])),
                                  Expanded(
                                    flex: 2,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          _incrementInvoiceLineQuantity(index),
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: EdgeInsets.symmetric(
                                            vertical: 12.h),
                                        color: Colors.teal.withOpacity(0.08),
                                        child: Text(
                                          amount.toStringAsFixed(1),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                      flex: 2,
                                      child: Text(
                                          price.toStringAsFixed(1),
                                          textAlign: TextAlign.center,
                                          style:
                                              TextStyle(fontSize: 13.sp))),
                                  Expanded(
                                    flex: 3,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: 12.h, horizontal: 6.w),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(p['product'],
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontSize: 13.sp,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            if (barcode.isNotEmpty)
                                              Text(barcode,
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                      fontSize: 10.sp,
                                                      color: Colors.grey)),
                                          ]),
                                    ),
                                  ),
                                ]),
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
                  ElevatedButton(
                    onPressed: _showCheckoutSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.75),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r)),
                      padding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 12.h),
                    ),
                    child: Text('حاسب',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold)),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────

class _SheetValueBox extends StatelessWidget {
  final String value;
  final Color? valueColor;
  const _SheetValueBox({required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(value,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87)),
    );
  }
}

class _PriceTierBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PriceTierBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34.w,
        height: 34.w,
        decoration: BoxDecoration(
          color: selected
              ? Colors.orange.withOpacity(0.85)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : Colors.black87)),
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(6.w),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Icon(icon, size: 18.sp),
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
  double quantity;
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
    );
  }
}

class _DrawerItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isDestructive;
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isDestructive = false,
  });
}
