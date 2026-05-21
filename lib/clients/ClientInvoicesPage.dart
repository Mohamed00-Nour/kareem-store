library client_invoices_page;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screeens/DecreaseProductPage.dart';
import '../Services/client_statement_pdf_service.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/whatsapp_invoice_share_service.dart';

part 'invoice_edit_sheet.dart';

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
  /// Opens edit sheet for the client sub-invoice linked to this root [invoices] id.
  final String? autoEditRootInvoiceId;

  const ClientInvoicesPage({
    Key? key,
    required this.clientId,
    this.autoEditRootInvoiceId,
  }) : super(key: key);

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
  bool _autoEditTriggered = false;
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

  double _numField(dynamic value) {
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is num) return value.toDouble();
    return 0.0;
  }

  Future<double> _productCostTotal(List<Map<String, dynamic>> products) async {
    double cost = 0;
    for (final p in products) {
      final name = p['product']?.toString() ?? '';
      if (name.isEmpty) continue;
      final amount = double.tryParse(p['amount']?.toString() ?? '') ?? 0;
      final q = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (q.docs.isEmpty) continue;
      final unitCost = (q.docs.first['costPrice'] as num?)?.toDouble() ?? 0;
      cost += amount * unitCost;
    }
    return cost;
  }

  Future<void> _syncRootSalesInvoice(
    String clientInvoiceDocId,
    Map<String, dynamic> fields,
  ) async {
    final clientRef = FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId)
        .collection('invoices')
        .doc(clientInvoiceDocId);
    final snap = await clientRef.get();
    if (!snap.exists) return;

    final data = snap.data();
    if (data == null) return;
    final rootId = data['invoiceId']?.toString();
    if (rootId == null || rootId.isEmpty) return;

    final rootRef =
        FirebaseFirestore.instance.collection('invoices').doc(rootId);
    final rootSnap = await rootRef.get();
    if (!rootSnap.exists) return;

    final rootUpdate = <String, dynamic>{};
    if (fields.containsKey('products')) {
      final products =
          List<Map<String, dynamic>>.from(fields['products'] as List);
      rootUpdate['products'] = products;
      final totalSum = fields.containsKey('totalSum')
          ? _numField(fields['totalSum'])
          : _numField(data['totalSum']);
      rootUpdate['totalSum'] = totalSum;
      rootUpdate['profitMargin'] = totalSum - await _productCostTotal(products);
    } else if (fields.containsKey('totalSum')) {
      final totalSum = _numField(fields['totalSum']);
      rootUpdate['totalSum'] = totalSum;
      final products = List<Map<String, dynamic>>.from(
        (data['products'] as List?) ?? [],
      );
      if (products.isNotEmpty) {
        rootUpdate['profitMargin'] =
            totalSum - await _productCostTotal(products);
      }
    }
    if (fields.containsKey('paidAmount')) {
      rootUpdate['paidAmount'] = _numField(fields['paidAmount']);
    }
    if (fields.containsKey('balance')) {
      rootUpdate['balance'] = _numField(fields['balance']);
    }

    if (rootUpdate.isNotEmpty) {
      await rootRef.update(rootUpdate);
    }
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

  Future<Map<String, dynamic>> _invoicePayloadForEdit(
      DocumentSnapshot invoice) async {
    final invoiceData = invoice.data() as Map<String, dynamic>;
    final rootId = invoiceData['invoiceId']?.toString();
    var payload = Map<String, dynamic>.from(invoiceData);
    payload['_clientSubDocId'] = invoice.id;

    if (rootId != null && rootId.isNotEmpty) {
      final rootSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .doc(rootId)
          .get();
      if (rootSnap.exists) {
        payload = {
          ...rootSnap.data()!,
          'id': rootId,
          '_clientSubDocId': invoice.id,
        };
      } else {
        payload['id'] = rootId;
      }
    }
    return payload;
  }

  Future<void> _showEditInvoiceDialog(DocumentSnapshot invoice) async {
    final payload = await _invoicePayloadForEdit(invoice);

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DecreaseProductPage(invoiceToEdit: payload),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تعديل الفاتورة بنجاح'),
      ));
      setState(() {});
      if (widget.autoEditRootInvoiceId != null) {
        Navigator.pop(context, true);
      }
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
                      RadioListTile<ClientStatementType>(
                        dense: true,
                        title: const Text('كشف حساب فواتير المرتجع'),
                        value: ClientStatementType.returns,
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
      String title;
      if (statementType == ClientStatementType.financial) {
        title = 'كشف حساب مالي';
      } else if (statementType == ClientStatementType.returns) {
        title = 'كشف حساب فواتير المرتجع';
      } else {
        title = 'كشف حساب الفواتير';
      }

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

  Widget _buildInvoiceProductsTable(List<dynamic> products) {
    final rows = products
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: const Text(
          'لا توجد منتجات في هذه الفاتورة',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    var qtySum = 0.0;
    for (final p in rows) {
      qtySum += double.tryParse(p['amount']?.toString() ?? '') ?? 0;
    }

    Widget cell(
      String text, {
      bool bold = false,
      TextAlign align = TextAlign.center,
    }) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
        child: Text(
          text,
          textAlign: align,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade400, width: 0.8),
      columnWidths: {
        0: const FlexColumnWidth(3),
        1: const FlexColumnWidth(1.1),
        2: const FlexColumnWidth(1.1),
        3: const FlexColumnWidth(1.2),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            cell('اسم المنتج', bold: true, align: TextAlign.right),
            cell('الكمية', bold: true),
            cell('السعر', bold: true),
            cell('الإجمالي', bold: true),
          ],
        ),
        for (final p in rows)
          TableRow(
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
            ),
            children: [
              cell(
                p['product']?.toString() ?? '',
                align: TextAlign.right,
              ),
              cell(p['amount']?.toString() ?? '0'),
              cell(
                (double.tryParse(p['selectedPrice']?.toString() ?? '') ?? 0)
                    .toStringAsFixed(2),
              ),
              cell(
                (double.tryParse(p['total']?.toString() ?? '') ?? 0)
                    .toStringAsFixed(2),
              ),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            cell(''),
            cell(qtySum.toStringAsFixed(1), bold: true),
            cell(''),
            cell(''),
          ],
        ),
      ],
    );
  }

  Future<void> _printInvoice(Map<String, dynamic> invoiceData) async {
    await InvoicePrintUi.printInvoice(
      context,
      invoiceData,
      clientId: widget.clientId,
    );
  }

  Future<void> _shareInvoiceOnWhatsApp(
      Map<String, dynamic> invoiceData) async {
    final data = Map<String, dynamic>.from(invoiceData);
    data['clientName'] ??= widget.clientId;
    await WhatsappInvoiceShareService.showShareOptions(
      context,
      invoice: data,
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

                    if (!_autoEditTriggered &&
                        widget.autoEditRootInvoiceId != null &&
                        invoices.isNotEmpty) {
                      _autoEditTriggered = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        for (final doc in invoices) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (data['invoiceId']?.toString() ==
                              widget.autoEditRootInvoiceId) {
                            _handleEditInvoice(doc);
                            break;
                          }
                        }
                      });
                    }

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
                                              icon: FaIcon(
                                                FontAwesomeIcons.whatsapp,
                                                color: Colors.green.shade700,
                                                size: 22,
                                              ),
                                              tooltip: 'مشاركة في واتساب',
                                              onPressed: () =>
                                                  _shareInvoiceOnWhatsApp(
                                                      invoiceData),
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
                                    SizedBox(height: 10.h),
                                    _buildInvoiceProductsTable(
                                      List<dynamic>.from(
                                        invoiceData['products'] ?? [],
                                      ),
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

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    customPriceCtrl.dispose();
    nameFocus.dispose();
  }
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
