import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl; 
import 'package:shared_preferences/shared_preferences.dart';

import 'SupplierBalanceHistoryPage.dart';

void _selectAllField(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

class SupplierInvoicesPage extends StatefulWidget {
  final String supplierId;

  const SupplierInvoicesPage({Key? key, required this.supplierId})
      : super(key: key);

  @override
  _SupplierInvoicesPageState createState() => _SupplierInvoicesPageState();
}

class _SupplierInvoicesPageState extends State<SupplierInvoicesPage> {
  final TextEditingController _balanceController = TextEditingController();
  double _enteredBalance = 0.0;
  String _userRole = 'user';
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  List<_SuppProdInfo> _allProds = [];
  final List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  Future<void> _fetchAllProds() async {
    try {
      final qs =
          await FirebaseFirestore.instance.collection('products').get();
      if (mounted) {
        setState(() {
          _allProds = qs.docs
              .map((doc) => _SuppProdInfo(
                    name: (doc['name'] ?? '').toString(),
                    costPrice:
                        (doc['costPrice'] as num?)?.toDouble() ?? 0.0,
                  ))
              .toList();
        });
      }
    } catch (_) {}
  }

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
    _fetchAllProds();
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

    final newBalance = currentBalance + enteredBalance;

    // Update supplier balance
    await supplierDoc.update({'totalBalance': newBalance});

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

      // Add change to the subcollection
      await boxDocRef.collection('changes').add({
        'date': FieldValue.serverTimestamp(),
        'value': enteredBalance,
        'type': 'decrement',
        'name': supplierName,
        'invoiceNumber': null, // No invoice number for balance entries
      });
    });

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
    if (mounted) {
      setState(() {
        _enteredBalance = 0.0;
      });
    }
  }
}



  // ─────────────────────────────────────────────
  // Edit invoice
  // ─────────────────────────────────────────────
  void _handleEditInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      _showEditSupplierInvoiceDialog(invoice);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  Future<void> _showEditSupplierInvoiceDialog(
      DocumentSnapshot invoice) async {
    final invoiceData = invoice.data() as Map<String, dynamic>;
    final List<Map<String, dynamic>> originalProducts =
        List<Map<String, dynamic>>.from(
            (invoiceData['products'] as List)
                .map((p) => Map<String, dynamic>.from(p)));

    final List<_SuppEditRow> rows = originalProducts.map((p) {
      final cost =
          double.tryParse(p['cost']?.toString() ?? '0') ?? 0.0;
      final amt =
          double.tryParse(p['amount']?.toString() ?? '1') ?? 1.0;
      _SuppProdInfo? info = _allProds.cast<_SuppProdInfo?>().firstWhere(
            (pi) => pi!.name == p['product']?.toString(),
            orElse: () => null,
          );
      info ??= _SuppProdInfo(
          name: p['product']?.toString() ?? '', costPrice: cost);
      return _SuppEditRow(
          prodInfo: info, amount: amt, costPrice: cost);
    }).toList();

    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        if (rows.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _selectAllField(rows.first.qtyCtrl);
          });
        }
        return StatefulBuilder(builder: (ctx, setSheet) {
          double invoiceTotal =
              rows.fold(0.0, (s, r) => s + r.totalCost);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.5,
              maxChildSize: 0.96,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin:
                        const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Text(
                        'الإجمالي: ${invoiceTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800),
                      ),
                      const Spacer(),
                      Text(
                        'فاتورة #${invoiceData['invoiceNumber']}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ]),
                  ),
                  const Divider(height: 16),
                  // Products list + add button
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      padding:
                          const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      itemCount: rows.length + 1,
                      itemBuilder: (_, i) {
                        if (i == rows.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => setSheet(() =>
                                  rows.add(_SuppEditRow(
                                    prodInfo: null,
                                    amount: 1.0,
                                    costPrice: 0.0,
                                  ))),
                              icon: const Icon(Icons.add,
                                  color: Colors.orange),
                              label: const Text('إضافة منتج',
                                  style: TextStyle(
                                      color: Colors.orange)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Colors.orange),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                            8)),
                              ),
                            ),
                          );
                        }
                        return _buildSupplierEditRowCard(
                            rows[i], i, rows, setSheet);
                      },
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom +
                          16,
                      top: 8,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('تراجع',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setSheet(() => isSaving = true);
                                  try {
                                    final updatedProducts = rows
                                        .where((r) =>
                                            r.prodInfo != null &&
                                            r.prodInfo!.name
                                                .isNotEmpty)
                                        .map((r) => {
                                              'product':
                                                  r.prodInfo!.name,
                                              'amount': r.amount
                                                  .toString(),
                                              'cost': r.costPrice
                                                  .toString(),
                                              'totalCost': r.totalCost
                                                  .toString(),
                                            })
                                        .toList();

                                    // Restore original stock
                                    // (buying invoice added stock, so restore = subtract)
                                    for (var op in originalProducts) {
                                      final oa = double.tryParse(
                                              op['amount']
                                                  .toString()) ??
                                          0.0;
                                      if (oa <= 0) continue;
                                      final q = await FirebaseFirestore
                                          .instance
                                          .collection('products')
                                          .where('name',
                                              isEqualTo:
                                                  op['product'])
                                          .get();
                                      for (var doc in q.docs) {
                                        final qty =
                                            (doc['quantity'] as num)
                                                .toDouble();
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .update(
                                                {'quantity': qty - oa});
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .collection('changes')
                                            .add({
                                          'date': DateTime.now(),
                                          'amount': oa,
                                          'type': 'decrease',
                                        });
                                      }
                                    }
                                    // Apply updated stock
                                    for (var np in updatedProducts) {
                                      final na = double.tryParse(
                                              np['amount']
                                                  .toString()) ??
                                          0.0;
                                      if (na <= 0) continue;
                                      final q = await FirebaseFirestore
                                          .instance
                                          .collection('products')
                                          .where('name',
                                              isEqualTo:
                                                  np['product'])
                                          .get();
                                      for (var doc in q.docs) {
                                        final qty =
                                            (doc['quantity'] as num)
                                                .toDouble();
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .update(
                                                {'quantity': qty + na});
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .collection('changes')
                                            .add({
                                          'date': DateTime.now(),
                                          'amount': na,
                                          'type': 'increase',
                                        });
                                      }
                                    }
                                    // Update invoice in supplier subcollection
                                    final double newTotalSum =
                                        updatedProducts.fold(
                                            0.0,
                                            (s, p) =>
                                                s +
                                                (double.tryParse(
                                                        p['totalCost']
                                                            .toString()) ??
                                                    0.0));
                                    await FirebaseFirestore.instance
                                        .collection('suppliers')
                                        .doc(widget.supplierId)
                                        .collection('buying invoices')
                                        .doc(invoice.id)
                                        .update({
                                      'products': updatedProducts,
                                      'totalSum': newTotalSum,
                                    });
                                    // Recalculate supplier balance
                                    final supplierDoc =
                                        FirebaseFirestore.instance
                                            .collection('suppliers')
                                            .doc(widget.supplierId);
                                    final allInv = await supplierDoc
                                        .collection('buying invoices')
                                        .get();
                                    double totalRemaining =
                                        allInv.docs.fold(
                                            0.0,
                                            (s, d) =>
                                                s +
                                                ((d['totalSum'] as num)
                                                        .toDouble() -
                                                    (d['paidAmount']
                                                            as num)
                                                        .toDouble()));
                                    final balHist = await supplierDoc
                                        .collection('balanceHistory')
                                        .get();
                                    double totalPaid = balHist.docs
                                        .fold(
                                            0.0,
                                            (s, d) =>
                                                s +
                                                ((d['enteredBalance']
                                                        is String)
                                                    ? double.tryParse(
                                                            d['enteredBalance']) ??
                                                        0.0
                                                    : (d['enteredBalance']
                                                            as num)
                                                        .toDouble()));
                                    await supplierDoc.update({
                                      'totalBalance':
                                          totalPaid - totalRemaining
                                    });

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'تم تعديل الفاتورة بنجاح')));
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                            content:
                                                Text('حدث خطأ: $e')));
                                    if (ctx.mounted) {
                                      setSheet(() => isSaving = false);
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('حفظ التعديلات',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                  ),
                ]);
              },
            ),
          );
        });
      },
    );
  }

  Widget _buildSupplierEditRowCard(
      _SuppEditRow row,
      int index,
      List<_SuppEditRow> rows,
      StateSetter setSheet) {
    return Card(
      key: ValueKey(row.key),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Product search + delete ──
            Row(children: [
              Expanded(
                child: RawAutocomplete<_SuppProdInfo>(
                  textEditingController: row.nameCtrl,
                  focusNode: row.nameFocus,
                  optionsBuilder: (val) {
                    if (val.text.isEmpty)
                      return const Iterable<_SuppProdInfo>.empty();
                    return _allProds.where((p) => p.name
                        .toLowerCase()
                        .contains(val.text.toLowerCase()));
                  },
                  displayStringForOption: (p) => p.name,
                  optionsViewBuilder: (ctx, onSel, opts) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: opts.length,
                            itemBuilder: (_, j) {
                              final p = opts.elementAt(j);
                              return ListTile(
                                dense: true,
                                title: Text(p.name,
                                    textAlign: TextAlign.right),
                                subtitle: Text(
                                    'سعر الشراء: ${p.costPrice.toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey)),
                                onTap: () => onSel(p),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder: (ctx, ctrl, focus, _) {
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        hintText: 'ابحث عن منتج',
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search,
                            size: 18, color: Colors.orange),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.orange, width: 2)),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 10),
                      ),
                      onTap: () => _selectAllField(ctrl),
                    );
                  },
                  onSelected: (p) {
                    setSheet(() {
                      row.prodInfo = p;
                      row.costPrice = p.costPrice;
                      row.costCtrl.text =
                          p.costPrice.toStringAsFixed(2);
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red),
                onPressed: () =>
                    setSheet(() => rows.removeAt(index)),
              ),
            ]),
            const SizedBox(height: 8),
            // ── Cost price + total ──
            Row(children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    row.totalCost.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: row.costCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'سعر الشراء',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Colors.orange, width: 2)),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                  ),
                  onTap: () => _selectAllField(row.costCtrl),
                  onChanged: (v) => setSheet(() =>
                      row.costPrice = double.tryParse(v) ?? 0.0),
                ),
              ),
              const SizedBox(width: 6),
              const Text('سعر | إجمالي',
                  style: TextStyle(fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            // ── Qty ──
            Row(children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    row.amount.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _SuppCircleBtn(
                icon: Icons.remove,
                onTap: () {
                  if (row.amount > 1) {
                    setSheet(() {
                      row.amount -= 1;
                      row.qtyCtrl.text =
                          row.amount.toStringAsFixed(1);
                    });
                  }
                },
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: row.qtyCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Colors.orange)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Colors.orange, width: 2)),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onTap: () => _selectAllField(row.qtyCtrl),
                  onChanged: (v) => setSheet(() =>
                      row.amount = double.tryParse(v) ?? row.amount),
                ),
              ),
              const SizedBox(width: 4),
              _SuppCircleBtn(
                icon: Icons.add,
                onTap: () => setSheet(() {
                  row.amount += 1;
                  row.qtyCtrl.text = row.amount.toStringAsFixed(1);
                }),
              ),
              const SizedBox(width: 6),
              const Text('الكمية',
                  style: TextStyle(fontSize: 12)),
            ]),
          ],
        ),
      ),
    );
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
    final supplierDoc = FirebaseFirestore.instance
        .collection('suppliers')
        .doc(widget.supplierId);

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

    final totalSum =
        (invoiceDoc.data()?['totalSum'] as num?)?.toDouble() ?? 0.0;
    final paidAmount =
        (invoiceDoc.data()?['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final invoiceRemaining = totalSum - paidAmount;

    final supplierSnapshot = await supplierDoc.get();
    final currentBalance = supplierSnapshot['totalBalance'] ?? 0.0;
    final updatedBalance = currentBalance + invoiceRemaining;

    await supplierDoc.update({'totalBalance': updatedBalance});

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

Future<void> _editProduct(String invoiceId, int productIndex, Map<String, dynamic> product) async {
  final TextEditingController productNameController =
      TextEditingController(text: product['product']);
  final TextEditingController amountController =
      TextEditingController(text: product['amount'].toString());
  final TextEditingController priceController =
      TextEditingController(text: product['cost'].toString());

  await showDialog(
    context: context,
    builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectAllField(amountController);
      });
      return AlertDialog(
        title: const Text('تعديل المنتج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: productNameController,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
              onTap: () => _selectAllField(productNameController),
            ),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية'),
              onTap: () => _selectAllField(amountController),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر'),
              onTap: () => _selectAllField(priceController),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final double updatedAmount = double.tryParse(amountController.text) ?? 0.0;
                final double updatedCost = double.tryParse(priceController.text) ?? 0.0;
                final double updatedTotalCost = updatedAmount * updatedCost;

                final updatedProduct = {
                  'product': productNameController.text,
                  'amount': updatedAmount,
                  'cost': updatedCost,
                  'totalCost': updatedTotalCost,
                };

                final invoiceDoc = FirebaseFirestore.instance
                    .collection('suppliers')
                    .doc(widget.supplierId)
                    .collection('buying invoices')
                    .doc(invoiceId);

                final invoiceSnapshot = await invoiceDoc.get();
                final products = List<Map<String, dynamic>>.from(invoiceSnapshot['products']);

                final double oldAmount = double.tryParse(product['amount'].toString()) ?? 0.0;
                final double amountDifference = updatedAmount - oldAmount;

                products[productIndex] = updatedProduct;

                double newTotalSum = products.fold(0.0, (sum, item) {
                  return sum + ((item['totalCost'] is String)
                      ? double.tryParse(item['totalCost']) ?? 0.0
                      : (item['totalCost'] as num).toDouble());
                });

                await invoiceDoc.update({
                  'products': products,
                  'totalSum': newTotalSum,
                });

                QuerySnapshot productQuery = await FirebaseFirestore.instance
                    .collection('products')
                    .where('name', isEqualTo: product['product'])
                    .get();

                if (productQuery.docs.isNotEmpty) {
                  for (var doc in productQuery.docs) {
                    int existingQuantity = (doc['quantity'] as num).toInt();
                    int updatedQuantity = existingQuantity + amountDifference.toInt();

                    await FirebaseFirestore.instance
                        .collection('products')
                        .doc(doc.id)
                        .update({'quantity': updatedQuantity});

                    await FirebaseFirestore.instance
                        .collection('products')
                        .doc(doc.id)
                        .collection('changes')
                        .add({
                      'date': DateTime.now(),
                      'amount': amountDifference.abs(),
                      'type': amountDifference > 0 ? 'increase' : 'decrease',
                    });
                  }
                }

                // Recalculate the supplier's balance
                final supplierDoc = FirebaseFirestore.instance
                    .collection('suppliers')
                    .doc(widget.supplierId);

                final invoicesSnapshot = await supplierDoc
                    .collection('buying invoices')
                    .get();

                double totalRemaining = invoicesSnapshot.docs.fold(0.0, (sum, doc) {
                  final totalSum = (doc['totalSum'] as num).toDouble();
                  final paidAmount = (doc['paidAmount'] as num).toDouble();
                  return sum + (totalSum - paidAmount);
                });

                final balanceHistorySnapshot = await supplierDoc
                    .collection('balanceHistory')
                    .get();

                double totalPaid = balanceHistorySnapshot.docs.fold(0.0, (sum, doc) {
                  return sum +
                      ((doc['enteredBalance'] is String)
                          ? double.tryParse(doc['enteredBalance']) ?? 0.0
                          : (doc['enteredBalance'] as num).toDouble());
                });

                final newBalance = totalPaid - totalRemaining;

                await supplierDoc.update({'totalBalance': newBalance});

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تعديل المنتج بنجاح')),
                );

                setState(() {});
                Navigator.of(context).pop();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('حدث خطأ: $e')),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
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
                  onChanged: (value) {
                    setState(() {
                      _enteredBalance = double.tryParse(value) ?? 0.0;
                    });
                  },
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
                    DateTime invoiceDate = invoice['date'].toDate().toLocal();
                    String formattedDate = invoiceDate.toString().split(' ')[0];
                    String formattedTime =
                      intl.DateFormat('hh:mm a').format(invoiceDate);

                    final invoiceData = invoice.data() as Map<String, dynamic>;

                    final previousBalance = invoiceData.containsKey('previousBalance')
                        ? (double.tryParse(invoiceData['previousBalance'].toString()) ?? 0.0)
                        : 0.0;


                    return Card(
                      margin: const EdgeInsets.all(10.0),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'رقم الفاتورة: #${invoice['invoiceNumber']}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          color: Colors.blue),
                                      onPressed: () =>
                                          _handleEditInvoice(invoice),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _handleDeleteInvoice(
                                              invoiceId, totalCost),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text('التاريخ: $formattedDate',
                                style: const TextStyle(fontSize: 14)),
                            Text('الوقت: $formattedTime',
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: const [
                                Text('المنتج',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Text('الكمية',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Text('السعر',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Text('الإجمالي',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: invoice['products'].length,
                              itemBuilder: (context, productIndex) {
                                final product =
                                    invoice['products'][productIndex];
                                final total = double.tryParse(
                                        product['totalCost'].toString()) ??
                                    0.0;

                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 3.0),
                                  elevation: 2,
                                  color: Colors.orange.withOpacity(0.8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        Text(
                                          product['product']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          (double.tryParse(product['amount'].toString()) ?? 0.0).toStringAsFixed(2),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          (double.tryParse(product['cost']
                                                      .toString()) ??
                                                  0.0)
                                              .toStringAsFixed(2),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(total.toStringAsFixed(2),
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        /*IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.black),
                                          onPressed: () => _editProduct(
                                              invoice.id,
                                              productIndex,
                                              product),
                                        ),*/
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'الرصيد السابق: ${previousBalance.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 30.w),
                                          Text(
                                            'إجمالي الفاتورة: ${(double.tryParse(invoice['totalSum'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'المدفوع: ${(double.tryParse(invoice['paidAmount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                      Text(
                                        'المتبقي: ${((double.tryParse(invoice['totalSum'].toString()) ?? 0.0) - (double.tryParse(invoice['paidAmount'].toString()) ?? 0.0)).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

// ────────────────────────────────────────────────────────────
// Helper models & widgets (supplier-scoped)
// ────────────────────────────────────────────────────────────

class _SuppProdInfo {
  final String name;
  final double costPrice;

  const _SuppProdInfo({required this.name, required this.costPrice});
}

class _SuppEditRow {
  final Key key;
  _SuppProdInfo? prodInfo;
  double amount;
  double costPrice;
  late final TextEditingController nameCtrl;
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;
  late final FocusNode nameFocus;

  _SuppEditRow({
    required this.prodInfo,
    required this.amount,
    required this.costPrice,
  }) : key = UniqueKey() {
    nameCtrl = TextEditingController(text: prodInfo?.name ?? '');
    qtyCtrl = TextEditingController(text: amount.toStringAsFixed(1));
    costCtrl = TextEditingController(text: costPrice.toStringAsFixed(2));
    nameFocus = FocusNode();
  }

  double get totalCost => amount * costPrice;
}

class _SuppCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SuppCircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
