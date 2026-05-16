import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/client_statement_pdf_service.dart';
import '../Services/invoice_print_service.dart';
import '../Services/printer_settings_service.dart';
import '../models/printer_settings.dart';

void _selectAllField(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

class ClientInvoicesPage extends StatefulWidget {
  final String clientId;

  const ClientInvoicesPage({Key? key, required this.clientId})
      : super(key: key);

  @override
  _ClientInvoicesPageState createState() => _ClientInvoicesPageState();
}

class _ClientInvoicesPageState extends State<ClientInvoicesPage> {
  final TextEditingController _balanceController = TextEditingController();
  double _enteredBalance = 0.0;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _isSaving = false; // Add loading state
  bool _generatingStatement = false;
  List<_ProdInfo> _allProds = [];

  Future<void> _fetchAllProds() async {
    try {
      final qs = await FirebaseFirestore.instance.collection('products').get();
      if (mounted) {
        setState(() {
          _allProds = qs.docs.map((doc) => _ProdInfo(
                name: (doc['name'] ?? '').toString(),
                sellingPrice1: (doc['sellingPrice1'] ?? 0.0).toDouble(),
                sellingPrice2: (doc['sellingPrice2'] ?? 0.0).toDouble(),
                sellingPrice3: (doc['sellingPrice3'] ?? 0.0).toDouble(),
                quantity: (doc['quantity'] as num?)?.toDouble() ?? 0.0,
              )).toList();
        });
      }
    } catch (_) {}
  }

  final List<String> _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

// In your ClientInvoicesPage, update the balance saving method

Future<void> _saveBalance() async {
  if (_balanceController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى إدخال المبلغ')),
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

  setState(() {
    _isSaving = true; // Show loading overlay
  });

  try {
    // Get current client balance
    DocumentSnapshot clientDoc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId)
        .get();

    double currentBalance = 0.0;
    String clientName = '';

    if (clientDoc.exists) {
      currentBalance = (clientDoc['balance'] ?? 0.0).toDouble();
      clientName = clientDoc['clientName'] ?? '';
    }

    double newBalance = currentBalance - enteredBalance;

    // Update client balance
    await FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId)
        .update({'balance': newBalance});

    // Add to client's balance history
    await FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId)
        .collection('balanceHistory')
        .add({
      'enteredBalance': enteredBalance,
      'balanceBefore': currentBalance,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update the box collection (same implementation as DecreaseProductPage)
    DocumentReference boxDocRef = FirebaseFirestore.instance
        .collection('box')
        .doc('mainBox');

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot boxSnapshot = await transaction.get(boxDocRef);

      if (boxSnapshot.exists) {
        double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
        transaction.update(boxDocRef, {'value': currentBoxValue + enteredBalance});
      } else {
        transaction.set(boxDocRef, {'value': enteredBalance});
      }

      // Add change to the subcollection
      await boxDocRef.collection('changes').add({
        'date': FieldValue.serverTimestamp(),
        'value': enteredBalance,
        'type': 'addition',
        'name': clientName,
        'invoiceNumber': null, // No invoice number for balance entries
      });
    });

    _balanceController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الرصيد بنجاح')),
    );

  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ في حفظ الرصيد: $e')),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isSaving = false; // Hide loading overlay
      });
    }
  }
}




  Future<void> _editProduct(String invoiceId, int productIndex, Map<String, dynamic> product) async {
    // Resolve product info from loaded list, fall back to stored prices
    final double storedPrice = double.tryParse(product['selectedPrice'].toString()) ?? 0.0;
    _ProdInfo? prodInfo = _allProds.cast<_ProdInfo?>().firstWhere(
      (p) => p!.name == product['product'].toString(),
      orElse: () => null,
    );
    prodInfo ??= _ProdInfo(
      name: product['product'].toString(),
      sellingPrice1: storedPrice,
      sellingPrice2: storedPrice,
      sellingPrice3: storedPrice,
      quantity: 0.0,
    );

    double amount = double.tryParse(product['amount'].toString()) ?? 1.0;
    double customPrice = storedPrice;

    // Detect price tier
    int priceTier = 0;
    if (storedPrice == prodInfo.sellingPrice1) priceTier = 1;
    else if (storedPrice == prodInfo.sellingPrice2) priceTier = 2;
    else if (storedPrice == prodInfo.sellingPrice3) priceTier = 3;

    bool isSaving = false;
    final TextEditingController qtyCtrl =
        TextEditingController(text: amount.toStringAsFixed(1));
    final TextEditingController customPriceCtrl =
        TextEditingController(text: customPrice.toStringAsFixed(2));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _selectAllField(qtyCtrl);
        });
        return StatefulBuilder(builder: (ctx, setSheet) {
          double price = prodInfo!.priceForTier(priceTier, customPrice);
          double total = amount * price;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Title ──
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text('تعديل منتج',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // ── Product search / autocomplete ──
                    Autocomplete<_ProdInfo>(
                      initialValue:
                          TextEditingValue(text: prodInfo!.name),
                      optionsBuilder: (val) {
                        if (val.text.isEmpty) {
                          return const Iterable<_ProdInfo>.empty();
                        }
                        return _allProds.where((p) => p.name
                            .toLowerCase()
                            .contains(val.text.toLowerCase()));
                      },
                      displayStringForOption: (p) => p.name,
                      optionsViewBuilder: (ctx2, onSelected, options) {
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
                                itemCount: options.length,
                                itemBuilder: (_, i) {
                                  final p = options.elementAt(i);
                                  return ListTile(
                                    dense: true,
                                    title: Text(p.name,
                                        textAlign: TextAlign.right),
                                    subtitle: Text(
                                        'س1: ${p.sellingPrice1.toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey)),
                                    onTap: () => onSelected(p),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      fieldViewBuilder: (ctx2, ctrl2, focus, _) {
                        return TextField(
                          controller: ctrl2,
                          focusNode: focus,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            labelText: 'ابحث عن منتج',
                            prefixIcon: const Icon(Icons.search,
                                color: Colors.orange),
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Colors.orange, width: 2)),
                          ),
                          onTap: () => _selectAllField(ctrl2),
                        );
                      },
                      onSelected: (p) {
                        setSheet(() {
                          prodInfo = p;
                          // Keep tier, update custom price reference
                          customPrice = p.priceForTier(priceTier, customPrice);
                          customPriceCtrl.text =
                              customPrice.toStringAsFixed(2);
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── Price tier + price display ──
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.grey.shade300),
                          ),
                          child: Text(
                            price.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PriceTierBtn(
                          label: '3',
                          selected: priceTier == 3,
                          onTap: () =>
                              setSheet(() => priceTier = 3)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: '2',
                          selected: priceTier == 2,
                          onTap: () =>
                              setSheet(() => priceTier = 2)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: '1',
                          selected: priceTier == 1,
                          onTap: () =>
                              setSheet(() => priceTier = 1)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: 'خ',
                          selected: priceTier == 0,
                          onTap: () =>
                              setSheet(() => priceTier = 0)),
                      const SizedBox(width: 8),
                      const Text('سعر البيع',
                          style: TextStyle(fontSize: 13)),
                    ]),

                    // ── Custom price input ──
                    if (priceTier == 0) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customPriceCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType
                            .numberWithOptions(decimal: true),
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'سعر خاص',
                          prefixIcon: const Icon(Icons.edit,
                              color: Colors.orange),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Colors.orange,
                                  width: 2)),
                        ),
                        onTap: () => _selectAllField(customPriceCtrl),
                        onChanged: (v) => setSheet(
                            () => customPrice =
                                double.tryParse(v) ?? 0.0),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── Total + Qty controls ──
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.shade200),
                          ),
                          child: Text(
                            total.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CircleBtn(
                          icon: Icons.remove,
                          onTap: () {
                            if (amount > 1) {
                              setSheet(() {
                                amount -= 1;
                                qtyCtrl.text =
                                    amount.toStringAsFixed(1);
                              });
                            }
                          }),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: qtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Colors.orange)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Colors.orange, width: 2)),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onTap: () => _selectAllField(qtyCtrl),
                          onChanged: (v) => setSheet(() =>
                              amount = double.tryParse(v) ?? amount),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _CircleBtn(
                          icon: Icons.add,
                          onTap: () => setSheet(() {
                                amount += 1;
                                qtyCtrl.text =
                                    amount.toStringAsFixed(1);
                              })),
                      const SizedBox(width: 8),
                      const Text('الكمية',
                          style: TextStyle(fontSize: 13)),
                    ]),
                    const SizedBox(height: 12),

                    // ── Available quantity ──
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الكمية المتوفرة',
                            style: TextStyle(fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              prodInfo!.quantity.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Action buttons ──
                    Row(children: [
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
                                vertical: 12),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setSheet(() => isSaving = true);
                                  try {
                                    final String newName =
                                        prodInfo!.name;
                                    final String oldName =
                                        product['product'].toString();
                                    final double oldAmount =
                                        double.tryParse(product[
                                                    'amount']
                                                .toString()) ??
                                            0.0;
                                    final double newAmount = amount;
                                    final double newPrice = prodInfo!
                                        .priceForTier(
                                            priceTier, customPrice);
                                    final double newTotal =
                                        newAmount * newPrice;

                                    // Restore old product quantity
                                    final oldQ =
                                        await FirebaseFirestore
                                            .instance
                                            .collection('products')
                                            .where('name',
                                                isEqualTo: oldName)
                                            .get();
                                    for (var doc in oldQ.docs) {
                                      final qty = (doc['quantity']
                                              as num)
                                          .toDouble();
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .update({
                                        'quantity': qty + oldAmount
                                      });
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .collection('changes')
                                          .add({
                                        'date': DateTime.now(),
                                        'amount': oldAmount,
                                        'type': 'increase',
                                      });
                                    }

                                    // Decrease new product quantity
                                    final newQ =
                                        await FirebaseFirestore
                                            .instance
                                            .collection('products')
                                            .where('name',
                                                isEqualTo: newName)
                                            .get();
                                    for (var doc in newQ.docs) {
                                      final qty = (doc['quantity']
                                              as num)
                                          .toDouble();
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .update({
                                        'quantity': qty - newAmount
                                      });
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .collection('changes')
                                          .add({
                                        'date': DateTime.now(),
                                        'amount': newAmount,
                                        'type': 'decrease',
                                      });
                                    }

                                    // Update invoice products list
                                    final invoiceRef = FirebaseFirestore
                                        .instance
                                        .collection('clients')
                                        .doc(widget.clientId)
                                        .collection('invoices')
                                        .doc(invoiceId);
                                    final snap =
                                        await invoiceRef.get();
                                    final List<
                                            Map<String, dynamic>>
                                        prods = List<
                                            Map<String,
                                                dynamic>>.from(
                                        snap['products']);
                                    prods[productIndex] = {
                                      'product': newName,
                                      'amount': newAmount.toString(),
                                      'selectedPrice':
                                          newPrice.toString(),
                                      'total': newTotal.toString(),
                                    };
                                    double newTotalSum =
                                        prods.fold(0.0, (s, p) =>
                                            s +
                                            (double.tryParse(p['total']
                                                    .toString()) ??
                                                0.0));
                                    await invoiceRef.update({
                                      'products': prods,
                                      'totalSum': newTotalSum,
                                    });

                                    // Recalculate client balance
                                    final allInv =
                                        await FirebaseFirestore
                                            .instance
                                            .collection('clients')
                                            .doc(widget.clientId)
                                            .collection('invoices')
                                            .get();
                                    double totalInv = allInv.docs
                                        .fold(0.0, (s, d) {
                                      return s +
                                          ((d['totalSum'] is String)
                                              ? double.tryParse(
                                                      d['totalSum']) ??
                                                  0.0
                                              : (d['totalSum'] as num)
                                                  .toDouble());
                                    });
                                    final balHist =
                                        await FirebaseFirestore
                                            .instance
                                            .collection('clients')
                                            .doc(widget.clientId)
                                            .collection(
                                                'balanceHistory')
                                            .get();
                                    double totalPaid = balHist.docs
                                        .fold(0.0, (s, d) {
                                      return s +
                                          ((d['enteredBalance']
                                                  is String)
                                              ? double.tryParse(d[
                                                      'enteredBalance']) ??
                                                  0.0
                                              : (d['enteredBalance']
                                                      as num)
                                                  .toDouble());
                                    });
                                    await FirebaseFirestore.instance
                                        .collection('clients')
                                        .doc(widget.clientId)
                                        .update({
                                      'balance': totalInv - totalPaid
                                    });

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'تم تعديل المنتج بنجاح')));
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                            content: Text(
                                                'حدث خطأ: $e')));
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
                              : const Text('متابعة',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _showEditInvoiceDialog(DocumentSnapshot invoice) async {
    final invoiceData = invoice.data() as Map<String, dynamic>;
    final List<Map<String, dynamic>> originalProducts =
        List<Map<String, dynamic>>.from(
            (invoiceData['products'] as List)
                .map((p) => Map<String, dynamic>.from(p)));

    // Build editable rows from existing products
    final List<_EditRow> rows = originalProducts.map((p) {
      final storedPrice =
          double.tryParse(p['selectedPrice'].toString()) ?? 0.0;
      _ProdInfo? info = _allProds.cast<_ProdInfo?>().firstWhere(
            (pi) => pi!.name == p['product'].toString(),
            orElse: () => null,
          );
      info ??= _ProdInfo(
        name: p['product'].toString(),
        sellingPrice1: storedPrice,
        sellingPrice2: storedPrice,
        sellingPrice3: storedPrice,
        quantity: 0.0,
      );
      int tier = 1;
      if (storedPrice == info.sellingPrice2) tier = 2;
      else if (storedPrice == info.sellingPrice3) tier = 3;
      else if (storedPrice != info.sellingPrice1) tier = 0;
      return _EditRow(
        prodInfo: info,
        amount: double.tryParse(p['amount'].toString()) ?? 1.0,
        priceTier: tier,
        customPrice: storedPrice,
      );
    }).toList();

    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        if (rows.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _selectAllField(rows.first.qtyCtrl);
          });
        }
        return StatefulBuilder(builder: (ctx, setSheet) {
          double invoiceTotal = rows.fold(0.0, (s, r) => s + r.total);
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
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ]),
                  ),
                  const Divider(height: 16),
                  // Products list + add button
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      itemCount: rows.length + 1,
                      itemBuilder: (_, i) {
                        if (i == rows.length) {
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => setSheet(() => rows.add(
                                  _EditRow(
                                    prodInfo: null,
                                    amount: 1.0,
                                    priceTier: 1,
                                    customPrice: 0.0,
                                  ))),
                              icon: const Icon(Icons.add,
                                  color: Colors.orange),
                              label: const Text('إضافة منتج',
                                  style:
                                      TextStyle(color: Colors.orange)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Colors.orange),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                          );
                        }
                        return _buildEditRowCard(
                            rows[i], i, rows, setSheet);
                      },
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom:
                          MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                                              'amount':
                                                  r.amount.toString(),
                                              'selectedPrice':
                                                  r.price.toString(),
                                              'total':
                                                  r.total.toString(),
                                            })
                                        .toList();

                                    // Restore original stock
                                    for (var op in originalProducts) {
                                      final oa = double.tryParse(
                                              op['amount'].toString()) ??
                                          0.0;
                                      if (oa <= 0) continue;
                                      final q = await FirebaseFirestore
                                          .instance
                                          .collection('products')
                                          .where('name',
                                              isEqualTo: op['product'])
                                          .get();
                                      for (var doc in q.docs) {
                                        final qty =
                                            (doc['quantity'] as num)
                                                .toDouble();
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .update(
                                                {'quantity': qty + oa});
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .collection('changes')
                                            .add({
                                          'date': DateTime.now(),
                                          'amount': oa,
                                          'type': 'increase',
                                        });
                                      }
                                    }
                                    // Apply updated stock
                                    for (var np in updatedProducts) {
                                      final na = double.tryParse(
                                              np['amount'].toString()) ??
                                          0.0;
                                      if (na <= 0) continue;
                                      final q = await FirebaseFirestore
                                          .instance
                                          .collection('products')
                                          .where('name',
                                              isEqualTo: np['product'])
                                          .get();
                                      for (var doc in q.docs) {
                                        final qty =
                                            (doc['quantity'] as num)
                                                .toDouble();
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .update(
                                                {'quantity': qty - na});
                                        await FirebaseFirestore.instance
                                            .collection('products')
                                            .doc(doc.id)
                                            .collection('changes')
                                            .add({
                                          'date': DateTime.now(),
                                          'amount': na,
                                          'type': 'decrease',
                                        });
                                      }
                                    }
                                    // Update invoice
                                    final double newTotalSum =
                                        updatedProducts.fold(
                                            0.0,
                                            (s, p) =>
                                                s +
                                                (double.tryParse(p['total']
                                                        .toString()) ??
                                                    0.0));
                                    await FirebaseFirestore.instance
                                        .collection('clients')
                                        .doc(widget.clientId)
                                        .collection('invoices')
                                        .doc(invoice.id)
                                        .update({
                                      'products': updatedProducts,
                                      'totalSum': newTotalSum,
                                    });
                                    // Recalculate client balance
                                    final allInv =
                                        await FirebaseFirestore.instance
                                            .collection('clients')
                                            .doc(widget.clientId)
                                            .collection('invoices')
                                            .get();
                                    double totalInv = allInv.docs.fold(
                                        0.0,
                                        (s, d) =>
                                            s +
                                            ((d['totalSum'] is String)
                                                ? double.tryParse(
                                                        d['totalSum']) ??
                                                    0.0
                                                : (d['totalSum'] as num)
                                                    .toDouble()));
                                    final balHist =
                                        await FirebaseFirestore.instance
                                            .collection('clients')
                                            .doc(widget.clientId)
                                            .collection('balanceHistory')
                                            .get();
                                    double totalPaid = balHist.docs.fold(
                                        0.0,
                                        (s, d) =>
                                            s +
                                            ((d['enteredBalance']
                                                    is String)
                                                ? double.tryParse(d[
                                                        'enteredBalance']) ??
                                                    0.0
                                                : (d['enteredBalance']
                                                        as num)
                                                    .toDouble()));
                                    await FirebaseFirestore.instance
                                        .collection('clients')
                                        .doc(widget.clientId)
                                        .update({
                                      'balance': totalInv - totalPaid
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

  Widget _buildEditRowCard(
      _EditRow row, int index, List<_EditRow> rows, StateSetter setSheet) {
    return Card(
      key: ValueKey(row.key),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Product search + delete ──
            Row(children: [
              Expanded(
                child: RawAutocomplete<_ProdInfo>(
                  textEditingController: row.nameCtrl,
                  focusNode: row.nameFocus,
                  optionsBuilder: (val) {
                    if (val.text.isEmpty)
                      return const Iterable<_ProdInfo>.empty();
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
                                    'س1: ${p.sellingPrice1.toStringAsFixed(2)}',
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
                            borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.orange, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 10),
                      ),
                      onTap: () => _selectAllField(ctrl),
                    );
                  },
                  onSelected: (p) {
                    setSheet(() {
                      row.prodInfo = p;
                      row.customPrice =
                          p.priceForTier(row.priceTier, row.customPrice);
                      row.customPriceCtrl.text =
                          row.customPrice.toStringAsFixed(2);
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setSheet(() => rows.removeAt(index)),
              ),
            ]),
            const SizedBox(height: 8),

            // ── Price tier + price display ──
            Row(children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    row.price.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _PriceTierBtn(
                label: '3',
                selected: row.priceTier == 3,
                onTap: () => setSheet(() => row.priceTier = 3),
              ),
              const SizedBox(width: 3),
              _PriceTierBtn(
                label: '2',
                selected: row.priceTier == 2,
                onTap: () => setSheet(() => row.priceTier = 2),
              ),
              const SizedBox(width: 3),
              _PriceTierBtn(
                label: '1',
                selected: row.priceTier == 1,
                onTap: () => setSheet(() => row.priceTier = 1),
              ),
              const SizedBox(width: 3),
              _PriceTierBtn(
                label: 'خ',
                selected: row.priceTier == 0,
                onTap: () => setSheet(() => row.priceTier = 0),
              ),
              const SizedBox(width: 6),
              const Text('السعر', style: TextStyle(fontSize: 12)),
            ]),

            // ── Custom price input ──
            if (row.priceTier == 0) ...[
              const SizedBox(height: 6),
              TextField(
                controller: row.customPriceCtrl,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'سعر خاص',
                  isDense: true,
                  prefixIcon: const Icon(Icons.edit,
                      color: Colors.orange, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Colors.orange, width: 2)),
                ),
                onTap: () => _selectAllField(row.customPriceCtrl),
                onChanged: (v) => setSheet(
                    () => row.customPrice = double.tryParse(v) ?? 0.0),
              ),
            ],
            const SizedBox(height: 8),

            // ── Qty + total ──
            Row(children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    row.total.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _CircleBtn(
                icon: Icons.remove,
                onTap: () {
                  if (row.amount > 1) {
                    setSheet(() {
                      row.amount -= 1;
                      row.qtyCtrl.text = row.amount.toStringAsFixed(1);
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.orange)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Colors.orange, width: 2)),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onTap: () => _selectAllField(row.qtyCtrl),
                  onChanged: (v) => setSheet(
                      () => row.amount = double.tryParse(v) ?? row.amount),
                ),
              ),
              const SizedBox(width: 4),
              _CircleBtn(
                icon: Icons.add,
                onTap: () => setSheet(() {
                  row.amount += 1;
                  row.qtyCtrl.text = row.amount.toStringAsFixed(1);
                }),
              ),
              const SizedBox(width: 6),
              const Text('الكمية', style: TextStyle(fontSize: 12)),
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
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmDelete != true) {
      return; // Exit if the user cancels the deletion
    }

    try {
      final clientDoc =
          FirebaseFirestore.instance.collection('clients').doc(widget.clientId);

      // Fetch the invoice to get the products
      final invoiceDoc = await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('invoices')
          .doc(invoiceId)
          .get();

      if (!invoiceDoc.exists) {
        throw Exception('الفاتورة غير موجودة');
      }

      final products = List<Map<String, dynamic>>.from(invoiceDoc['products']);

      // Add the product's amount back to the product's quantity
      for (var product in products) {
        QuerySnapshot productQuery = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: product['product'])
            .get();

        if (productQuery.docs.isNotEmpty) {
          for (var doc in productQuery.docs) {
            double existingQuantity = doc['quantity'];
            double restoredQuantity =
                existingQuantity + double.parse(product['amount']);

            // Update the product's quantity
            await FirebaseFirestore.instance
                .collection('products')
                .doc(doc.id)
                .update({'quantity': restoredQuantity});

            // Log the change in the product's `changes` subcollection
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

      // Delete the invoice
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('invoices')
          .doc(invoiceId)
          .delete();

      // Update the client's balance
      final clientSnapshot = await clientDoc.get();
      final currentBalance = clientSnapshot['balance'] ?? 0.0;
      final updatedBalance = currentBalance - totalCost;

      await clientDoc.update({'balance': updatedBalance});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفاتورة بنجاح')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء حذف الفاتورة: $e')),
      );
    }
  }

  String _userRole = 'user'; // Default to user role

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

  void _handleDeleteInvoice(String invoiceId, double totalCost) {
    if (_userRole == 'admin') {
      _deleteInvoice(invoiceId, totalCost);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _handleEditInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      _showEditInvoiceDialog(invoice);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  Future<void> _pickDate(
    BuildContext ctx,
    DateTime initial,
    void Function(DateTime) onPicked,
  ) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _showAccountStatementDialog() async {
    ClientStatementType statementType = ClientStatementType.financial;
    DateTime from = DateTime(_selectedYear, _selectedMonth, 1);
    DateTime to = DateTime(_selectedYear, _selectedMonth + 1, 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setDialog) {
              return AlertDialog(
                backgroundColor: const Color(0xffead1ac),
                title: const Text(
                  'كشف حساب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('نوع الكشف',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      RadioListTile<ClientStatementType>(
                        dense: true,
                        title: const Text('كشف حساب مالي (الدفعات فقط)'),
                        value: ClientStatementType.financial,
                        groupValue: statementType,
                        onChanged: (v) =>
                            setDialog(() => statementType = v!),
                      ),
                      RadioListTile<ClientStatementType>(
                        dense: true,
                        title: const Text('كشف حساب الفواتير'),
                        value: ClientStatementType.invoices,
                        groupValue: statementType,
                        onChanged: (v) =>
                            setDialog(() => statementType = v!),
                      ),
                      const SizedBox(height: 12),
                      const Text('الفترة',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('من تاريخ'),
                        subtitle: Text(intl.DateFormat('dd/MM/yyyy').format(from)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _pickDate(ctx, from, (d) {
                          setDialog(() => from = d);
                        }),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إلى تاريخ'),
                        subtitle: Text(intl.DateFormat('dd/MM/yyyy').format(to)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _pickDate(ctx, to, (d) {
                          setDialog(() => to = d);
                        }),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (to.isBefore(from)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'تاريخ النهاية يجب أن يكون بعد تاريخ البداية'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('إنشاء PDF'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _generatingStatement = true);
    try {
      final file = await ClientStatementPdfService.generate(
        clientId: widget.clientId,
        type: statementType,
        from: from,
        to: to,
      );

      if (!mounted) return;
      final title = statementType == ClientStatementType.financial
          ? 'كشف حساب مالي'
          : 'كشف حساب الفواتير';

      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: const Text('تم إنشاء التقرير. ماذا تريد أن تفعل؟'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('مشاركة'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Share.shareXFiles([XFile(file.path)], text: title);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('فتح'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await OpenFilex.open(file.path);
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingStatement = false);
    }
  }

  Future<void> _printInvoice(Map<String, dynamic> invoiceData) async {
    final settings = await PrinterSettingsService.load();
    if (settings.connectionType != PrinterConnectionType.bluetooth) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار طابعة Bluetooth من إعدادات الطابعة'),
        ),
      );
      return;
    }
    if (settings.bluetoothMacAddress.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ربط الطابعة من إعدادات الطابعة أولاً'),
        ),
      );
      return;
    }

    final invoice = Map<String, dynamic>.from(invoiceData);
    invoice['clientName'] = widget.clientId;

    final totalSum =
        double.tryParse(invoice['totalSum']?.toString() ?? '') ?? 0.0;
    final paidAmount =
        double.tryParse(invoice['paidAmount']?.toString() ?? '') ?? 0.0;
    invoice['balance'] = totalSum - paidAmount;

    final mainInvoiceId = invoice['invoiceId']?.toString();
    if (mainInvoiceId != null && mainInvoiceId.isNotEmpty) {
      try {
        final mainDoc = await FirebaseFirestore.instance
            .collection('invoices')
            .doc(mainInvoiceId)
            .get();
        if (mainDoc.exists && mainDoc.data() != null) {
          invoice.addAll(mainDoc.data()!);
          invoice['clientName'] =
              mainDoc.data()!['clientName'] ?? widget.clientId;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري الطباعة...')),
    );

    final ok = await InvoicePrintService.printSalesInvoice(invoice);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'تمت طباعة الفاتورة' : 'فشلت طباعة الفاتورة'),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.7),
            title: const Text('فواتير العميل' , style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            )),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                tooltip: 'كشف حساب PDF',
                onPressed: (_isSaving || _generatingStatement)
                    ? null
                    : _showAccountStatementDialog,
              ),
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
                      enabled: !_isSaving, // Disable during saving
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
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              backgroundColor: (_isSaving || _generatingStatement)
                                  ? Colors.grey
                                  : Colors.orange.shade800),
                          onPressed: (_isSaving || _generatingStatement)
                              ? null
                              : _showAccountStatementDialog,
                          child: _generatingStatement
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'كشف حساب PDF',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              backgroundColor: _isSaving
                                  ? Colors.grey
                                  : Colors.black.withOpacity(0.7)),
                          onPressed: _isSaving ? null : _saveBalance, // Disable when saving
                          child: _isSaving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'حفظ',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white.withOpacity(1),
                                  ),
                                ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              backgroundColor: Colors.black.withOpacity(0.7)),
                          onPressed: _isSaving ? null : () { // Disable when saving
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) =>
                                  BalanceHistoryPage(clientId: widget.clientId),
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
                      .collection('clients')
                      .doc(widget.clientId)
                      .collection('invoices')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: Colors.orange.withOpacity(0.7)));
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
                        final invoiceRef = invoices[index].reference;
                        return FutureBuilder<DocumentSnapshot>(
                          future: invoiceRef.get(),
                          builder: (context, invoiceSnapshot) {
                            if (!invoiceSnapshot.hasData) {
                              return Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.orange.withOpacity(0.7)));
                            }

                            final invoice = invoiceSnapshot.data!;
                            DateTime invoiceDate =
                                invoice['date'].toDate().toLocal();
                            String formattedDate =
                                invoiceDate.toString().split(' ')[0];
                            String formattedTime =
                                intl.DateFormat('hh:mm a').format(invoiceDate);

                            final invoiceData = invoice.data() as Map<String, dynamic>;

                            final previousBalance = invoiceData.containsKey('previousBalance')
                                ? (double.tryParse(invoiceData['previousBalance'].toString()) ?? 0.0)
                                : 0.0;

                            final totalSum = invoiceData.containsKey('totalSum')
                                ? (double.tryParse(invoiceData['totalSum'].toString()) ?? 0.0)
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
                                                fontWeight: FontWeight.bold)),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.print_outlined,
                                                  color: Colors.black87),
                                              tooltip: 'طباعة',
                                              onPressed: () =>
                                                  _printInvoice(invoiceData),
                                            ),
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
                                                      invoice.id,
                                                      invoice['totalSum']),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text('التاريخ: $formattedDate',
                                        style: const TextStyle(fontSize: 14)),
                                    Text('$formattedTime :الوقت ',
                                        style: const TextStyle(fontSize: 14)),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
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
                                      itemBuilder: (context, index) {
                                        final product = invoice['products'][index];
                                        final total = double.tryParse(
                                                product['total'].toString()) ??
                                            0.0;

                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 3.0),
                                          elevation: 2,
                                          color: Colors.orange.withOpacity(0.8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                Text(product['product'],
                                                    style: const TextStyle(
                                                        fontSize: 12)),
                                                Text(product['amount'],
                                                    style: const TextStyle(
                                                        fontSize: 12)),
                                                Text(
                                                  (double.tryParse(product[
                                                                  'selectedPrice']
                                                              .toString()) ??
                                                          0.0)
                                                      .toStringAsFixed(2),
                                                  style:
                                                      const TextStyle(fontSize: 12),
                                                ),
                                                Text(total.toStringAsFixed(2),
                                                    style: const TextStyle(
                                                        fontSize: 12)),
                                               /* IconButton(
                                                  icon: const Icon(Icons.edit,
                                                      color: Colors.black),
                                                  onPressed: () => _editProduct(
                                                      invoice.id, index, product),
                                                ),*/
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
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
                                                  SizedBox(width: 20.w,),
                                                  Text(
                                                    'إجمالي الفاتورة: ${totalSum.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                'المدفوع: ${(double.tryParse(invoice['paidAmount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 16,
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Loading overlay
        if (_isSaving || _generatingStatement)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12.h),
                  
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class BalanceHistoryPage extends StatelessWidget {
  final String clientId;

  const BalanceHistoryPage({Key? key, required this.clientId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاريخ الرصيد'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clients')
            .doc(clientId)
            .collection('balanceHistory')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data!.docs;

          return DataTable(
            columns: const [
              DataColumn(label: Text('الرصيد المدخل')),
              DataColumn(label: Text('الرصيد قبل')),
              DataColumn(label: Text('التاريخ')),
            ],
            rows: history.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = (data['timestamp'] as Timestamp).toDate();
              final formattedDate = intl.DateFormat('yyyy-MM-dd').format(timestamp);

              return DataRow(cells: [
                DataCell(Text((data['enteredBalance'] as num).toStringAsFixed(2))), // Format to 2 decimal places
                DataCell(Text((data['balanceBefore'] as num).toStringAsFixed(2))),
                DataCell(Text(formattedDate)),
              ]);
            }).toList(),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Data model for product lookup
// ──────────────────────────────────────────────────────────────
class _ProdInfo {
  final String name;
  final double sellingPrice1;
  final double sellingPrice2;
  final double sellingPrice3;
  final double quantity;

  const _ProdInfo({
    required this.name,
    required this.sellingPrice1,
    required this.sellingPrice2,
    required this.sellingPrice3,
    required this.quantity,
  });

  double priceForTier(int tier, double custom) {
    if (tier == 0) return custom;
    switch (tier) {
      case 2:
        return sellingPrice2;
      case 3:
        return sellingPrice3;
      default:
        return sellingPrice1;
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Editable row for invoice edit dialog
// ──────────────────────────────────────────────────────────────
class _EditRow {
  final Key key;
  _ProdInfo? prodInfo;
  double amount;
  int priceTier;
  double customPrice;
  late final TextEditingController nameCtrl;
  late final TextEditingController qtyCtrl;
  late final TextEditingController customPriceCtrl;
  late final FocusNode nameFocus;

  _EditRow({
    required this.prodInfo,
    required this.amount,
    required this.priceTier,
    required this.customPrice,
  }) : key = UniqueKey() {
    nameCtrl = TextEditingController(text: prodInfo?.name ?? '');
    qtyCtrl = TextEditingController(text: amount.toStringAsFixed(1));
    customPriceCtrl =
        TextEditingController(text: customPrice.toStringAsFixed(2));
    nameFocus = FocusNode();
  }

  double get price =>
      prodInfo?.priceForTier(priceTier, customPrice) ?? customPrice;
  double get total => amount * price;
}

// ──────────────────────────────────────────────────────────────
// Helper widgets
// ──────────────────────────────────────────────────────────────
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
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: selected
              ? Colors.orange.withOpacity(0.85)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
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
