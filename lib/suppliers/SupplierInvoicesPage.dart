import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/supplier_invoice_balance_sync_service.dart';
import '../Widgets/invoice_display_widgets.dart';
import '../Screeens/AddProductPage.dart';
import 'SupplierBalanceHistoryPage.dart';



class SupplierInvoicesPage extends StatefulWidget {
  final String supplierId;

  const SupplierInvoicesPage({Key? key, required this.supplierId})
      : super(key: key);

  @override
  _SupplierInvoicesPageState createState() => _SupplierInvoicesPageState();
}

class _SupplierInvoicesPageState extends State<SupplierInvoicesPage> {
  final TextEditingController _balanceController = TextEditingController();
  String _userRole = 'user';
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  final List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  Future<void> _loadUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userRole = prefs.getString('user_role') ?? 'user';
      });
    } catch (e) {
      print('Error loading user role: $e');
    }
  }

  Future<void> _handleDeleteInvoice(String invoiceId, double totalCost) async {
    if (_userRole == 'admin') {
      _deleteInvoice(invoiceId, totalCost);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ليس لديك صلاحية'),
          content: Text('ليس لديك الصلاحية لحذف الفواتير'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _syncSupplierInvoiceBalances();
  }

  Future<void> _syncSupplierInvoiceBalances() async {
    try {
      await SupplierInvoiceBalanceSyncService.syncForSupplier(
          widget.supplierId);
      if (mounted) setState(() {});
    } catch (_) {
      // Non-blocking backfill on open.
    }
  }


Future<void> _saveBalance() async {
  if (_balanceController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('من فضلك أدخل الرصيد')),
    );
    return;
  }

  double enteredBalance = double.tryParse(_balanceController.text) ?? 0.0;
  if (enteredBalance <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Center(
      child: CircularProgressIndicator(
        color: Colors.orange.withOpacity(0.7),
      ),
    ),
  );

  try {
    // Get current supplier data
    final supplierDoc = FirebaseFirestore.instance
        .collection('suppliers')
        .doc(widget.supplierId);
    final supplierSnapshot = await supplierDoc.get();
    final currentBalance = supplierSnapshot['totalBalance'] ?? 0.0;

    // Try different possible field names for supplier name
    final supplierName = supplierSnapshot['name'];

    // Add to supplier's balance history
    await supplierDoc.collection('balanceHistory').add({
      'enteredBalance': enteredBalance,
      'balanceBefore': currentBalance,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update the box collection - decrease the balance from box
    DocumentReference boxDocRef = FirebaseFirestore.instance
        .collection('box')
        .doc('mainBox');

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot boxSnapshot = await transaction.get(boxDocRef);

      if (boxSnapshot.exists) {
        double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
        transaction.update(boxDocRef, {'value': currentBoxValue - enteredBalance});
      } else {
        transaction.set(boxDocRef, {'value': -enteredBalance});
      }
    });

    // Add change to the subcollection
    await boxDocRef.collection('changes').add({
      'date': FieldValue.serverTimestamp(),
      'value': enteredBalance,
      'type': 'decrement',
      'name': supplierName,
      'invoiceNumber': null, // No invoice number for balance entries
    });

    await SupplierInvoiceBalanceSyncService.syncForSupplier(widget.supplierId);

    if (mounted) Navigator.of(context).pop();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الحفظ بنجاح')),
      );
    }
  } catch (e) {
    if (mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    }
  } finally {
    _balanceController.clear();
  }
}

  // ─────────────────────────────────────────────
  // Edit invoice
  // ─────────────────────────────────────────────
  void _handleEditInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      final invoiceData = Map<String, dynamic>.from(invoice.data() as Map);
      invoiceData['id'] = invoiceData['invoiceId'] ?? invoice.id;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddProductPage(invoiceToEdit: invoiceData),
        ),
      );
    } else {
      _showPermissionDeniedDialog();
    }
  }

  Future<void> _deleteInvoice(String invoiceId, double totalCost) async {
  final confirmDelete = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد أنك تريد حذف هذه الفاتورة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      );
    },
  );

  if (confirmDelete != true) {
    return;
  }

  try {
    final invoiceDoc = await FirebaseFirestore.instance
        .collection('suppliers')
        .doc(widget.supplierId)
        .collection('buying invoices')
        .doc(invoiceId)
        .get();

    if (!invoiceDoc.exists) {
      throw Exception('الفاتورة غير موجودة');
    }

    final products = List<Map<String, dynamic>>.from(invoiceDoc['products']);

    for (var product in products) {
      QuerySnapshot productQuery = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: product['product'])
          .get();

      if (productQuery.docs.isNotEmpty) {
        for (var doc in productQuery.docs) {
          int existingQuantity = (doc['quantity'] as num).toInt();
          int restoredQuantity = existingQuantity -
              (double.parse(product['amount'].toString())).round();

          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .update({'quantity': restoredQuantity});

          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': DateTime.now(),
            'amount': product['amount'],
            'type': 'increase',
          });
        }
      }
    }

    await FirebaseFirestore.instance
        .collection('suppliers')
        .doc(widget.supplierId)
        .collection('buying invoices')
        .doc(invoiceId)
        .delete();

    await SupplierInvoiceBalanceSyncService.syncForSupplier(widget.supplierId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الفاتورة بنجاح')),
    );
  } catch (e) {
    print(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('حدث خطأ أثناء حذف الفاتورة: $e')),
    );
  }
}





  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        title: const Text('فواتير المورد' , style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          DropdownButton<int>(
            value: _selectedYear,
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            underline: SizedBox(),
            selectedItemBuilder: (context) {
              return List.generate(6, (index) {
                int year = DateTime.now().year - index;
                return Align(
                  alignment: Alignment.center,
                  child: Text(year.toString(), style: const TextStyle(color: Colors.white)),
                );
              });
            },
            items: List.generate(6, (index) {
              int year = DateTime.now().year - index;
              return DropdownMenuItem(
                value: year,
                child: Text(year.toString(), style: const TextStyle(color: Colors.black)),
              );
            }),
            onChanged: (value) {
              setState(() {
                _selectedYear = value!;
              });
            },
          ),
          DropdownButton<int>(
            value: _selectedMonth,
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            underline: SizedBox(),
            selectedItemBuilder: (context) {
              return List.generate(12, (index) {
                return Align(
                  alignment: Alignment.center,
                  child: Text(_arabicMonths[index], style: const TextStyle(color: Colors.white)),
                );
              });
            },
            items: List.generate(12, (index) {
              return DropdownMenuItem(
                value: index + 1,
                child: Text(_arabicMonths[index], style: const TextStyle(color: Colors.black)),
              );
            }),
            onChanged: (value) {
              setState(() {
                _selectedMonth = value!;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              children: [
                TextField(
                  controller: _balanceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.black.withOpacity(0.7)),
                    ),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                    labelText: 'أدخل الرصيد',
                    labelStyle: TextStyle(
                      color: Colors.black.withOpacity(0.7),
                      fontSize: 16,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7),
                      ),
                      onPressed: _saveBalance,
                      child: Text(
                        'حفظ',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.7),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => SupplierBalanceHistoryPage(
                              supplierId: widget.supplierId),
                        ));
                      },
                      child: Text(
                        'عرض تاريخ الرصيد',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('suppliers')
                  .doc(widget.supplierId)
                  .collection('buying invoices')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Colors.orange.withOpacity(0.7),
                    ),
                  );
                }

                final invoices = snapshot.data!.docs.where((doc) {
                  final date = doc['date']?.toDate();
                  return date != null &&
                    date.year == _selectedYear &&
                    date.month == _selectedMonth;
                }).toList();

                return ListView.builder(
                  itemCount: invoices.length,
                  itemBuilder: (context, index) {
                    final invoice = invoices[index];
                    final invoiceId = invoice.id;
                    final totalCost = (invoice['totalSum'] as num).toDouble();
                    final invoiceData =
                        invoice.data() as Map<String, dynamic>;

                    return InvoiceDisplayCard(
                      invoice: invoiceData,
                      kind: InvoiceDisplayKind.purchase,
                      actions: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _handleEditInvoice(invoice),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _handleDeleteInvoice(invoiceId, totalCost),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

