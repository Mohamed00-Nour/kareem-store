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
import '../Services/client_invoice_balance_sync_service.dart';
import '../Services/client_statement_pdf_service.dart';
import '../Services/invoice_number_utils.dart';
import '../Services/sales_invoice_actions_service.dart';
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
  static const int _invoicePageSize = 20;
  String? _clientName;
  double? _currentClientBalance;

  final TextEditingController _balanceController = TextEditingController();
  final TextEditingController _addBalanceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ScrollController _invoiceScrollController = ScrollController();
  bool _isSaving = false; // Add loading state
  bool _generatingStatement = false;
  bool _autoEditTriggered = false;
  List<_ProdInfo> _allProds = [];

  List<QueryDocumentSnapshot> _invoices = [];
  List<QueryDocumentSnapshot> _returnInvoices = [];
  List<QueryDocumentSnapshot> _payments = [];
  DocumentSnapshot? _lastInvoiceDoc;
  bool _isLoadingInvoices = true;
  bool _isLoadingMoreInvoices = false;
  bool _hasMoreInvoices = true;
  bool _showPayments = false; // toggle: show payment cards in the list
  final Set<String> _expandedInvoiceIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<void> _fetchAllProds() async {
    try {
      final qs = await FirebaseFirestore.instance.collection('products').get();
      if (mounted) {
        setState(() {
          _allProds = qs.docs
              .map((doc) {
                final docData = doc.data() as Map<String, dynamic>?;
                return _ProdInfo(
                  name: (docData?['name'] ?? '').toString(),
                  sellingPrice1: (docData?['sellingPrice1'] ?? 0.0).toDouble(),
                  sellingPrice2: (docData?['sellingPrice2'] ?? 0.0).toDouble(),
                  sellingPrice3: (docData?['sellingPrice3'] ?? 0.0).toDouble(),
                  quantity: (docData?['quantity'] as num?)?.toDouble() ?? 0.0,
                );
              })
              .toList();
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

  Query _invoicesQuery() => FirebaseFirestore.instance
      .collection('clients')
      .doc(widget.clientId)
      .collection('invoices')
      .orderBy('date', descending: true);

  Query _returnInvoicesQuery() => FirebaseFirestore.instance
      .collection('clients')
      .doc(widget.clientId)
      .collection('returnInvoices')
      .orderBy('date', descending: true);

  Query _paymentsQuery() => FirebaseFirestore.instance
      .collection('clients')
      .doc(widget.clientId)
      .collection('balanceHistory')
      .orderBy('timestamp', descending: true);

  void _onInvoiceScroll() {
    if (!_invoiceScrollController.hasClients || _searchQuery.isNotEmpty) return;
    final pos = _invoiceScrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    _loadMoreInvoices();
  }

  Future<void> _fetchInvoices({bool reset = false}) async {
    if (reset) {
      if (!mounted) return;
      setState(() {
        _isLoadingInvoices = true;
        _invoices = [];
        _returnInvoices = [];
        _payments = [];
        _lastInvoiceDoc = null;
        _hasMoreInvoices = true;
      });
    } else {
      if (_isLoadingMoreInvoices || !_hasMoreInvoices || _isLoadingInvoices) {
        return;
      }
      setState(() => _isLoadingMoreInvoices = true);
    }

    try {
      Query query = _invoicesQuery().limit(_invoicePageSize);
      if (!reset && _lastInvoiceDoc != null) {
        query = query.startAfterDocument(_lastInvoiceDoc!);
      }

      // Fetch invoices, returnInvoices, and payments in parallel on reset
      final Future<QuerySnapshot> invoiceFuture = query.get();
      final Future<QuerySnapshot?> returnFuture = reset
          ? _returnInvoicesQuery().get()
          : Future<QuerySnapshot?>.value(null);
      final Future<QuerySnapshot?> paymentFuture = reset
          ? _paymentsQuery().get()
          : Future<QuerySnapshot?>.value(null);
      final snap = await invoiceFuture;
      final retSnap = await returnFuture;
      // Fetch payments separately with its own error guard (needs a Firestore index;
      // if the index doesn't exist yet, degrade gracefully instead of crashing)
      QuerySnapshot? paySnap;
      try {
        paySnap = await paymentFuture;
      } catch (_) {
        paySnap = null;
      }
      if (!mounted) return;

      setState(() {
        if (reset) {
          _invoices = snap.docs;
          _returnInvoices = retSnap?.docs ?? [];
          // Exclude 'sale' and 'return' types — those are shown as invoice cards
          _payments = (paySnap?.docs ?? []).where((doc) {
            final t = (doc.data() as Map<String, dynamic>)['type']?.toString() ?? '';
            return t != 'sale' && t != 'return';
          }).toList();
        } else {
          _invoices.addAll(snap.docs);
        }
        if (snap.docs.isNotEmpty) {
          _lastInvoiceDoc = snap.docs.last;
        }
        _hasMoreInvoices = snap.docs.length >= _invoicePageSize;
        _isLoadingInvoices = false;
        _isLoadingMoreInvoices = false;
      });

      if (reset) {
        await _tryAutoEditInvoice();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingInvoices = false;
        _isLoadingMoreInvoices = false;
      });
    }
  }

  Future<void> _loadMoreInvoices() => _fetchInvoices(reset: false);

  Future<void> _refreshInvoices() async {
    _fetchClientName();
    await _fetchInvoices(reset: true);
  }

  Future<void> _tryAutoEditInvoice() async {
    if (_autoEditTriggered || widget.autoEditRootInvoiceId == null) return;

    for (final doc in _invoices) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['invoiceId']?.toString() == widget.autoEditRootInvoiceId) {
        _autoEditTriggered = true;
        _handleEditInvoice(doc);
        return;
      }
    }

    final q = await FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId)
        .collection('invoices')
        .where('invoiceId', isEqualTo: widget.autoEditRootInvoiceId)
        .limit(1)
        .get();
    if (!mounted || q.docs.isEmpty) return;
    _autoEditTriggered = true;
    _handleEditInvoice(q.docs.first);
  }

// In your ClientInvoicesPage, update the balance saving method

  Future<void> _saveBalance() async {
    final deductText = _balanceController.text.trim();
    final addText = _addBalanceController.text.trim();
    final notesText = _notesController.text.trim();

    if (deductText.isEmpty && addText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال المبلغ')),
      );
      return;
    }

    final isAddition = addText.isNotEmpty;
    final valueText = isAddition ? addText : deductText;
    double enteredBalance = double.tryParse(valueText) ?? 0.0;

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
        final clientData = clientDoc.data() as Map<String, dynamic>?;
        currentBalance = (clientData?['balance'] ?? 0.0).toDouble();
        clientName = clientData?['clientName'] ?? '';
      }

      double newBalance = isAddition
          ? currentBalance + enteredBalance
          : currentBalance - enteredBalance;

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
        'type': isAddition ? 'addition' : 'deduction',
        'notes': notesText,
        'timestamp': DateTime.now(), // local timestamp so it's immediately queryable
      });

      // Update the box collection
      DocumentReference boxDocRef =
          FirebaseFirestore.instance.collection('box').doc('mainBox');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot boxSnapshot = await transaction.get(boxDocRef);

        if (boxSnapshot.exists) {
          double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
          transaction.update(boxDocRef, {
            'value': isAddition
                ? currentBoxValue - enteredBalance
                : currentBoxValue + enteredBalance
          });
        } else {
          transaction.set(boxDocRef,
              {'value': isAddition ? -enteredBalance : enteredBalance});
        }
      });

      // Add change to the subcollection
      await boxDocRef.collection('changes').add({
        'date': FieldValue.serverTimestamp(),
        'value': enteredBalance,
        'type': isAddition ? 'decrement' : 'addition',
        'name': clientName,
        'notes': notesText,
        'invoiceNumber': null, // No invoice number for balance entries
      });

      _balanceController.clear();
      _addBalanceController.clear();
      _notesController.clear();

      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);
      _fetchClientName();
      _refreshInvoices();

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

  Future<void> _editProduct(
      String invoiceId, int productIndex, Map<String, dynamic> product) async {
    // Resolve product info from loaded list, fall back to stored prices
    final double storedPrice =
        double.tryParse(product['selectedPrice'].toString()) ?? 0.0;
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
    if (storedPrice == prodInfo.sellingPrice1)
      priceTier = 1;
    else if (storedPrice == prodInfo.sellingPrice2)
      priceTier = 2;
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
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // ── Product search / autocomplete ──
                    Autocomplete<_ProdInfo>(
                      initialValue: TextEditingValue(text: prodInfo!.name),
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
                              constraints: const BoxConstraints(maxHeight: 200),
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
                                            fontSize: 11, color: Colors.grey)),
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
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.orange),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
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
                          customPriceCtrl.text = customPrice.toStringAsFixed(2);
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
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            price.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PriceTierBtn(
                          label: '3',
                          selected: priceTier == 3,
                          onTap: () => setSheet(() => priceTier = 3)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: '2',
                          selected: priceTier == 2,
                          onTap: () => setSheet(() => priceTier = 2)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: '1',
                          selected: priceTier == 1,
                          onTap: () => setSheet(() => priceTier = 1)),
                      const SizedBox(width: 4),
                      _PriceTierBtn(
                          label: 'خ',
                          selected: priceTier == 0,
                          onTap: () => setSheet(() => priceTier = 0)),
                      const SizedBox(width: 8),
                      const Text('سعر البيع', style: TextStyle(fontSize: 13)),
                    ]),

                    // ── Custom price input ──
                    if (priceTier == 0) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customPriceCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'سعر خاص',
                          prefixIcon:
                              const Icon(Icons.edit, color: Colors.orange),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Colors.orange, width: 2)),
                        ),
                        onTap: () => _selectAllField(customPriceCtrl),
                        onChanged: (v) => setSheet(
                            () => customPrice = double.tryParse(v) ?? 0.0),
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
                            border: Border.all(color: Colors.orange.shade200),
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
                                qtyCtrl.text = amount.toStringAsFixed(1);
                              });
                            }
                          }),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: qtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700),
                          decoration: InputDecoration(
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
                          onTap: () => _selectAllField(qtyCtrl),
                          onChanged: (v) => setSheet(
                              () => amount = double.tryParse(v) ?? amount),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _CircleBtn(
                          icon: Icons.add,
                          onTap: () => setSheet(() {
                                amount += 1;
                                qtyCtrl.text = amount.toStringAsFixed(1);
                              })),
                      const SizedBox(width: 8),
                      const Text('الكمية', style: TextStyle(fontSize: 13)),
                    ]),
                    const SizedBox(height: 12),

                    // ── Available quantity ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الكمية المتوفرة',
                            style: TextStyle(fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(prodInfo!.quantity.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
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
                            backgroundColor: Colors.orange.withOpacity(0.85),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setSheet(() => isSaving = true);
                                  try {
                                    final String newName = prodInfo!.name;
                                    final String oldName =
                                        product['product'].toString();
                                    final double oldAmount = double.tryParse(
                                            product['amount'].toString()) ??
                                        0.0;
                                    final double newAmount = amount;
                                    final double newPrice = prodInfo!
                                        .priceForTier(priceTier, customPrice);
                                    final double newTotal =
                                        newAmount * newPrice;

                                    // Restore old product quantity
                                    final oldQ = await FirebaseFirestore
                                        .instance
                                        .collection('products')
                                        .where('name', isEqualTo: oldName)
                                        .get();
                                    for (var doc in oldQ.docs) {
                                      final docData = doc.data() as Map<String, dynamic>?;
                                      final qty =
                                          ((docData?['quantity'] ?? 0.0) as num).toDouble();
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .update(
                                              {'quantity': qty + oldAmount});
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
                                    final newQ = await FirebaseFirestore
                                        .instance
                                        .collection('products')
                                        .where('name', isEqualTo: newName)
                                        .get();
                                    for (var doc in newQ.docs) {
                                      final docData = doc.data() as Map<String, dynamic>?;
                                      final qty =
                                          ((docData?['quantity'] ?? 0.0) as num).toDouble();
                                      await FirebaseFirestore.instance
                                          .collection('products')
                                          .doc(doc.id)
                                          .update(
                                              {'quantity': qty - newAmount});
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
                                    final snap = await invoiceRef.get();
                                    final snapData = snap.data() as Map<String, dynamic>?;
                                    final List<Map<String, dynamic>> prods =
                                        List<Map<String, dynamic>>.from(
                                            snapData?['products'] ?? []);
                                    prods[productIndex] = {
                                      'product': newName,
                                      'amount': newAmount.toString(),
                                      'selectedPrice': newPrice.toString(),
                                      'total': newTotal.toString(),
                                    };
                                    double newTotalSum = prods.fold(
                                        0.0,
                                        (s, p) =>
                                            s +
                                            (double.tryParse(
                                                    p['total'].toString()) ??
                                                0.0));
                                    await invoiceRef.update({
                                      'products': prods,
                                      'totalSum': newTotalSum,
                                    });

                                    await ClientInvoiceBalanceSyncService
                                        .syncForClient(widget.clientId);

                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('تم تعديل المنتج بنجاح')));
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('حدث خطأ: $e')));
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
                                      strokeWidth: 2, color: Colors.white))
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
    return SalesInvoiceActionsService.buildEditPayload(
      invoiceData,
      clientSubDocId: invoice.id,
    );
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
      await _refreshInvoices();
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

      final invoiceData = invoiceDoc.data() as Map<String, dynamic>?;
      final products = List<Map<String, dynamic>>.from(invoiceData?['products'] ?? []);

      // Add the product's amount back to the product's quantity
      for (var product in products) {
        QuerySnapshot productQuery = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: product['product'])
            .get();

        if (productQuery.docs.isNotEmpty) {
          for (var doc in productQuery.docs) {
            final docData = doc.data() as Map<String, dynamic>?;
            double existingQuantity = (docData?['quantity'] ?? 0.0).toDouble();
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

      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفاتورة بنجاح')),
      );
      await _refreshInvoices();
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

  // ── Return-invoice edit / delete ─────────────────────────────────

  Future<void> _showEditReturnInvoiceDialog(DocumentSnapshot invoice) async {
    final payload = await _invoicePayloadForEdit(invoice);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DecreaseProductPage(
          isReturnInvoice: true,
          invoiceToEdit: payload,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تعديل فاتورة المرتجع بنجاح'),
      ));
      await _refreshInvoices();
    }
  }

  Future<void> _deleteReturnInvoice(DocumentSnapshot clientSubDoc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
            'هل أنت متأكد من حذف فاتورة المرتجع؟\nسيتم عكس جميع التأثيرات على المخزون والرصيد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('إلغاء',
                style: TextStyle(color: Colors.black.withOpacity(0.7))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final data = clientSubDoc.data() as Map<String, dynamic>;
      final products =
          List<Map<String, dynamic>>.from(data['products'] as List? ?? []);
      final rootInvoiceId = data['invoiceId']?.toString() ?? '';

      // 1. Reverse the stock restore (return invoice added stock, so delete must subtract)
      for (final product in products) {
        final name = product['product']?.toString() ?? '';
        if (name.isEmpty) continue;
        final amount =
            double.tryParse(product['amount']?.toString() ?? '0') ?? 0.0;
        if (amount <= 0) continue;

        final q = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: name)
            .get();
        for (final pDoc in q.docs) {
          final qty = (pDoc['quantity'] as num?)?.toDouble() ?? 0.0;
          await FirebaseFirestore.instance
              .collection('products')
              .doc(pDoc.id)
              .update({'quantity': qty - amount});
          await FirebaseFirestore.instance
              .collection('products')
              .doc(pDoc.id)
              .collection('changes')
              .add({
            'date': DateTime.now(),
            'amount': amount,
            'type': 'decrease',
          });
        }
      }

      // 2. Delete root returnInvoice document
      if (rootInvoiceId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('returnInvoices')
            .doc(rootInvoiceId)
            .delete();
      }

      // 3. Delete client sub-document
      await clientSubDoc.reference.delete();

      // 4. Remove related balanceHistory entries (type 'return' and 'return_payment')
      if (rootInvoiceId.isNotEmpty) {
        final historySnap = await FirebaseFirestore.instance
            .collection('clients')
            .doc(widget.clientId)
            .collection('balanceHistory')
            .where('invoiceId', isEqualTo: rootInvoiceId)
            .get();
        final batch = FirebaseFirestore.instance.batch();
        for (final h in historySnap.docs) {
          batch.delete(h.reference);
        }
        await batch.commit();
      }

      // 5. Re-sync client balance
      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف فاتورة المرتجع بنجاح')),
        );
        await _refreshInvoices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف المرتجع: $e')),
        );
      }
    }
  }

  void _handleEditReturnInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      _showEditReturnInvoiceDialog(invoice);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _handleDeleteReturnInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      _deleteReturnInvoice(invoice);
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
    final now = DateTime.now();
    DateTime from = DateTime(now.year, now.month, 1);
    DateTime to = DateTime(now.year, now.month + 1, 0);

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
                        onChanged: (v) => setDialog(() => statementType = v!),
                      ),
                      RadioListTile<ClientStatementType>(
                        dense: true,
                        title: const Text('كشف حساب الفواتير'),
                        value: ClientStatementType.invoices,
                        groupValue: statementType,
                        onChanged: (v) => setDialog(() => statementType = v!),
                      ),
                      RadioListTile<ClientStatementType>(
                        dense: true,
                        title: const Text('كشف حساب فواتير المرتجع'),
                        value: ClientStatementType.returns,
                        groupValue: statementType,
                        onChanged: (v) => setDialog(() => statementType = v!),
                      ),
                      const SizedBox(height: 12),
                      const Text('الفترة',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('من تاريخ'),
                        subtitle:
                            Text(intl.DateFormat('dd/MM/yyyy').format(from)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () => _pickDate(ctx, from, (d) {
                          setDialog(() => from = d);
                        }),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إلى تاريخ'),
                        subtitle:
                            Text(intl.DateFormat('dd/MM/yyyy').format(to)),
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

  void _showBalanceActionDialog() {
    _balanceController.clear();
    _addBalanceController.clear();
    _notesController.clear();

    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xffead1ac),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r)),
            title: const Text(
              'تعديل رصيد العميل',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                      labelText: 'خصم من الرصيد (سداد)',
                      labelStyle: TextStyle(
                        color: Colors.black.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        _addBalanceController.clear();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addBalanceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                      labelText: 'إضافة إلى الرصيد',
                      labelStyle: TextStyle(
                        color: Colors.black.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.green,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        _balanceController.clear();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                      labelText: 'البيان / ملاحظات العملية (اختياري)',
                      labelStyle: TextStyle(
                        color: Colors.black.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.note_alt_outlined,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: Text(
                  'إلغاء',
                  style: TextStyle(color: Colors.black.withOpacity(0.7)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveBalance();
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToBalanceHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => BalanceHistoryPage(clientId: widget.clientId),
    ));
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

    // Only show the discount column if at least one product has a discount.
    final hasAnyDiscount = rows.any(
      (p) => ((p['discount'] as num?)?.toDouble() ?? 0.0) > 0,
    );

    if (!hasAnyDiscount) {
      // ── 4-column table (no discount column) ──
      return Table(
        border: TableBorder.all(color: Colors.grey.shade400, width: 0.8),
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(1.1),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.2),
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
              decoration:
                  BoxDecoration(color: Colors.orange.withOpacity(0.12)),
              children: [
                cell(invoiceProductName(p), align: TextAlign.right),
                cell(invoiceQty(p['amount'])),
                cell(invoiceAmount(p['selectedPrice'])),
                cell(invoiceAmount(p['total'])),
              ],
            ),
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              cell(''),
              cell(invoiceQty(qtySum), bold: true),
              cell(''),
              cell(''),
            ],
          ),
        ],
      );
    }

    // ── 5-column table (with discount column) ──
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.1),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.2),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            cell('اسم المنتج', bold: true, align: TextAlign.right),
            cell('الكمية', bold: true),
            cell('السعر', bold: true),
            cell('الخصم', bold: true),
            cell('الإجمالي', bold: true),
          ],
        ),
        for (final p in rows) ...[
          () {
            final discount = (p['discount'] as num?)?.toDouble() ?? 0.0;
            final discountIsPercent = p['discountIsPercent'] == true;
            final hasDiscount = discount > 0;
            final discountLabel = hasDiscount
                ? (discountIsPercent
                    ? '${discount.toStringAsFixed(1)}%'
                    : invoiceAmount(discount))
                : '';
            return TableRow(
              decoration: BoxDecoration(
                color: hasDiscount
                    ? Colors.orange.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.12),
              ),
              children: [
                cell(invoiceProductName(p), align: TextAlign.right),
                cell(invoiceQty(p['amount'])),
                cell(invoiceAmount(p['selectedPrice'])),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                  child: Text(
                    discountLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight:
                          hasDiscount ? FontWeight.bold : FontWeight.normal,
                      color: hasDiscount
                          ? Colors.red.shade700
                          : Colors.transparent,
                    ),
                  ),
                ),
                cell(invoiceAmount(p['total']), bold: hasDiscount),
              ],
            );
          }(),
        ],
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            cell(''),
            cell(invoiceQty(qtySum), bold: true),
            cell(''),
            cell(''),
            cell(''),
          ],
        ),
      ],
    );
  }

  // ── Payment card ──────────────────────────────────────────────
  Widget _buildPaymentCard(_InvoiceEntry entry) {
    final data = entry.data;
    final type = data['type']?.toString() ?? 'deduction';
    final amount = (data['enteredBalance'] as num?)?.toDouble() ?? 0.0;
    final notes = (data['notes'] ?? data['description'] ?? '').toString().trim();
    final ts = data['timestamp'];
    final date = ts is Timestamp ? ts.toDate().toLocal() : null;
    final formattedDate =
        date != null ? intl.DateFormat('yyyy-MM-dd').format(date) : '';
    final formattedTime =
        date != null ? intl.DateFormat('hh:mm a').format(date) : '';
    final invoiceNumber = data['invoiceNumber']?.toString() ?? '';

    // Label, icon and colours per type
    String label;
    IconData icon;
    Color badgeColor;
    Color cardColor;
    Color amountColor;
    String sign;

    switch (type) {
      case 'sale_payment':
        label = 'سداد فاتورة';
        icon = Icons.payments_outlined;
        badgeColor = Colors.green.shade700;
        cardColor = Colors.green.shade50;
        amountColor = Colors.green.shade800;
        sign = '+';
        break;
      case 'return_payment':
        label = 'سداد مرتجع';
        icon = Icons.undo_outlined;
        badgeColor = Colors.teal.shade700;
        cardColor = Colors.teal.shade50;
        amountColor = Colors.teal.shade800;
        sign = '-';
        break;
      case 'addition':
        label = 'إضافة رصيد';
        icon = Icons.add_circle_outline;
        badgeColor = Colors.orange.shade700;
        cardColor = Colors.orange.shade50;
        amountColor = Colors.orange.shade800;
        sign = '+';
        break;
      case 'opening':
        label = 'رصيد افتتاحي';
        icon = Icons.account_balance_outlined;
        badgeColor = Colors.blue.shade700;
        cardColor = Colors.blue.shade50;
        amountColor = Colors.blue.shade800;
        sign = '';
        break;
      default: // deduction
        label = 'خصم (سداد)';
        icon = Icons.payments_outlined;
        badgeColor = Colors.green.shade700;
        cardColor = Colors.green.shade50;
        amountColor = Colors.green.shade800;
        sign = '+';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: badgeColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon circle
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            // Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (invoiceNumber.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'فاتورة #$invoiceNumber',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notes,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (formattedDate.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$formattedDate  $formattedTime',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Amount
            Text(
              '$sign${amount.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printInvoice(Map<String, dynamic> invoiceData) async {
    await InvoicePrintUi.printInvoice(
      context,
      invoiceData,
      clientId: widget.clientId,
    );
  }

  Future<void> _shareInvoiceOnWhatsApp(Map<String, dynamic> invoiceData) async {
    final data = Map<String, dynamic>.from(invoiceData);
    data['clientName'] ??= _clientName ?? widget.clientId;
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
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim();
        });
      }
    });
    _loadUserRole();
    _fetchAllProds();
    _fetchClientName();
    _invoiceScrollController.addListener(_onInvoiceScroll);
    _fetchInvoices(reset: true);
    _syncClientInvoiceBalances();
  }

  Future<void> _fetchClientName() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .get();
      if (snap.exists && mounted) {
        setState(() {
          _clientName = snap.data()?['clientName']?.toString();
          _currentClientBalance = (snap.data()?['balance'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _syncClientInvoiceBalances() async {
    try {
      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);
      // Only refresh the client balance display — invoices were already
      // loaded by _fetchInvoices(reset: true) in initState.
      if (mounted) await _fetchClientName();
    } catch (_) {
      // Non-blocking backfill on open.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _invoiceScrollController.removeListener(_onInvoiceScroll);
    _invoiceScrollController.dispose();
    _balanceController.dispose();
    _addBalanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Returns the effective DateTime for sorting any entry in the unified list.
  static DateTime _entryDate(_InvoiceEntry e) {
    final d = e.data;
    if (e.kind == _EntryKind.payment) {
      final ts = d['timestamp'];
      if (ts is Timestamp) return ts.toDate();
      if (ts is DateTime) return ts;
      // Pending server timestamp or null → treat as 'just now' so new entries sort first
      return DateTime.now();
    }
    final ts = d['date'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return DateTime(0);
  }

  /// Combines sales invoices, return invoices, and payment entries sorted newest first.
  List<_InvoiceEntry> get _allMergedInvoices {
    final List<_InvoiceEntry> merged = [
      ..._invoices.map((d) => _InvoiceEntry(doc: d, kind: _EntryKind.invoice)),
      ..._returnInvoices.map((d) => _InvoiceEntry(doc: d, kind: _EntryKind.returnInvoice)),
      ..._payments.map((d) => _InvoiceEntry(doc: d, kind: _EntryKind.payment)),
    ];
    merged.sort((a, b) => _entryDate(b).compareTo(_entryDate(a)));
    return merged;
  }

  List<_InvoiceEntry> get _filteredInvoices {
    final all = _allMergedInvoices;
    // Always strip payment entries when the payments toggle is off
    final visible = _showPayments
        ? all
        : all.where((e) => e.kind != _EntryKind.payment).toList();
    if (_searchQuery.isEmpty) return visible;
    final q = _searchQuery.toLowerCase();
    return visible.where((entry) {
      final data = entry.data;
      if (entry.kind == _EntryKind.payment) {
        // Search payments by notes or amount
        final notes = (data['notes'] ?? data['description'] ?? '').toString().toLowerCase();
        final amount = (data['enteredBalance'] ?? 0).toString();
        return notes.contains(q) || amount.contains(q);
      }
      final num = data['invoiceNumber']?.toString() ?? '';
      if (num.contains(q)) return true;
      final products = data['products'] as List? ?? [];
      for (final p in products) {
        if (p is Map) {
          final prodName = (p['product'] ?? '').toString().toLowerCase();
          if (prodName.contains(q)) return true;
        }
      }
      return false;
    }).toList();
  }

  Widget _buildInvoiceCard(_InvoiceEntry entry) {
    // Dispatch payment entries to their own card builder
    if (entry.kind == _EntryKind.payment) return _buildPaymentCard(entry);

    final invoice = entry.doc;
    final bool isReturn = entry.kind == _EntryKind.returnInvoice;
    final invoiceData = Map<String, dynamic>.from(invoice.data() as Map);
    final dateField = invoiceData['date'];
    if (dateField is! Timestamp) {
      return const SizedBox.shrink();
    }

    final invoiceDate = dateField.toDate().toLocal();
    final formattedDate = invoiceDate.toString().split(' ')[0];
    final formattedTime = intl.DateFormat('hh:mm a').format(invoiceDate);

    final previousBalance = invoiceDynamicPreviousBalance(invoiceData);
    final remainingOwed = invoiceClientRemainingOwed(invoiceData);

    final totalSum = invoiceData.containsKey('totalSum')
        ? (double.tryParse(invoiceData['totalSum'].toString()) ?? 0.0)
        : 0.0;
    double discount = invoiceNum(invoiceData['invoiceDiscount']);
    if (discount <= 0) {
      final double productsSum =
          (invoiceData['products'] as List? ?? []).fold<double>(
        0.0,
        (sum, item) {
          if (item is! Map) return sum;
          final itemTotal = double.tryParse(
                  (item['total'] ?? item['totalCost'])?.toString() ?? '') ??
              0.0;
          return sum + itemTotal;
        },
      );
      final diff = productsSum - totalSum;
      if (diff > 0.01) {
        discount = diff;
      }
    }

    final invoiceId = invoice.id;
    final isExpanded = _expandedInvoiceIds.contains(invoiceId);

    return Card(
      margin: const EdgeInsets.all(10.0),
      color: isReturn ? Colors.red.shade50 : null,
      shape: isReturn
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.red.shade200, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedInvoiceIds.remove(invoiceId);
                        } else {
                          _expandedInvoiceIds.add(invoiceId);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isReturn)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade700,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'مرتجع',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    'رقم الفاتورة: #${invoice['invoiceNumber']} (${invoiceAmount(totalSum)} ج.م)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      decoration: isReturn
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: Colors.red.shade700,
                                      decorationThickness: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: isReturn
                                ? Colors.red.shade700
                                : Colors.orange.shade800,
                          ),
                          SizedBox(width: 8.w),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.print_outlined,
                          color: Colors.black87),
                      tooltip: 'طباعة',
                      onPressed: () => _printInvoice(invoiceData),
                    ),
                    IconButton(
                      icon: FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Colors.green.shade700,
                        size: 22,
                      ),
                      tooltip: 'مشاركة في واتساب',
                      onPressed: () => _shareInvoiceOnWhatsApp(invoiceData),
                    ),
                    if (!isReturn) ...[
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _handleEditInvoice(invoice),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _handleDeleteInvoice(
                          invoice.id,
                          invoice['totalSum'],
                        ),
                      ),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.edit,
                            color: Colors.deepOrangeAccent),
                        tooltip: 'تعديل المرتجع',
                        onPressed: () => _handleEditReturnInvoice(invoice),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.red),
                        tooltip: 'حذف المرتجع',
                        onPressed: () => _handleDeleteReturnInvoice(invoice),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 5),
              Text('التاريخ: $formattedDate',
                  style: const TextStyle(fontSize: 14)),
              Text('$formattedTime :الوقت ',
                  style: const TextStyle(fontSize: 14)),
              SizedBox(height: 10.h),
              _buildInvoiceProductsTable(
                List<dynamic>.from(invoiceData['products'] ?? []),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Text(
                              'الرصيد السابق: ${invoiceAmount(previousBalance)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 20.w),
                            Text(
                              'إجمالي الفاتورة: ${invoiceAmount(totalSum)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (discount > 0)
                          Text(
                            'خصم الفاتورة: ${invoiceAmount(discount)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        Text(
                          'المدفوع: ${invoiceAmount(invoice['paidAmount'])}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'المتبقي من الفاتورة: ${invoiceAmount(totalSum - invoiceNum(invoice['paidAmount']))}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          'المتبقي عليكم: ${invoiceAmount(remainingOwed)}',
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.7),
            title: const Text('فواتير العميل',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                )),
            actions: [
              // Toggle: show / hide payment cards
              IconButton(
                tooltip: _showPayments ? 'إخفاء الدفعات' : 'عرض الدفعات',
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    _showPayments
                        ? Icons.payments
                        : Icons.payments_outlined,
                    key: ValueKey(_showPayments),
                    color: _showPayments
                        ? Colors.greenAccent.shade200
                        : Colors.white,
                  ),
                ),
                onPressed: (_isSaving || _generatingStatement)
                    ? null
                    : () => setState(() => _showPayments = !_showPayments),
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                tooltip: 'تاريخ الرصيد',
                onPressed: (_isSaving || _generatingStatement)
                    ? null
                    : _navigateToBalanceHistory,
              ),
              IconButton(
                icon: const Icon(Icons.account_balance_wallet,
                    color: Colors.white),
                tooltip: 'تعديل الرصيد',
                onPressed: (_isSaving || _generatingStatement)
                    ? null
                    : _showBalanceActionDialog,
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                tooltip: 'كشف حساب PDF',
                onPressed: (_isSaving || _generatingStatement)
                    ? null
                    : _showAccountStatementDialog,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: TextField(
                    controller: _searchController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'ابحث برقم الفاتورة أو اسم المنتج...',
                      hintStyle: TextStyle(fontSize: 14.sp),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.orange),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            const BorderSide(color: Colors.orange, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingInvoices && _invoices.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Colors.orange.withOpacity(0.7),
                        ),
                      )
                    : _filteredInvoices.isEmpty
                        ? const Center(child: Text('لا توجد فواتير مطابقة'))
                        : RefreshIndicator(
                            onRefresh: _refreshInvoices,
                            color: Colors.orange,
                            child: ListView.builder(
                              controller: _invoiceScrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _filteredInvoices.length +
                                  (_hasMoreInvoices || _isLoadingMoreInvoices
                                      ? 1
                                      : 0),
                              itemBuilder: (context, index) {
                                if (index >= _filteredInvoices.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.orange.withOpacity(0.7),
                                      ),
                                    ),
                                  );
                                }
                                return _buildInvoiceCard(_filteredInvoices[index]);
                              },
                            ),
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

class BalanceHistoryPage extends StatefulWidget {
  final String clientId;

  const BalanceHistoryPage({Key? key, required this.clientId})
      : super(key: key);

  @override
  State<BalanceHistoryPage> createState() => _BalanceHistoryPageState();
}

class _BalanceHistoryPageState extends State<BalanceHistoryPage> {
  bool _isBusy = false;

  static int _typePriority(String type) {
    switch (type) {
      case 'opening':
        return 7;
      case 'sale_payment':
        return 1;
      case 'sale':
        return 2;
      case 'return_payment':
        return 3;
      case 'return':
        return 4;
      case 'addition':
        return 5;
      case 'deduction':
        return 6;
      default:
        return 8;
    }
  }

  static List<QueryDocumentSnapshot> _sortDocs(
      List<QueryDocumentSnapshot> docs) {
    final sorted = List<QueryDocumentSnapshot>.from(docs);
    sorted.sort((a, b) {
      final dataA = a.data() as Map<String, dynamic>;
      final dataB = b.data() as Map<String, dynamic>;
      final typeA = dataA['type']?.toString() ?? '';
      final typeB = dataB['type']?.toString() ?? '';

      // Opening always last (oldest) in a descending list
      if (typeA == 'opening' && typeB != 'opening') return 1;
      if (typeB == 'opening' && typeA != 'opening') return -1;

      // Group by same invoiceId
      final invA = dataA['invoiceId']?.toString() ?? '';
      final invB = dataB['invoiceId']?.toString() ?? '';
      if (invA.isNotEmpty && invA == invB) {
        return _typePriority(typeA).compareTo(_typePriority(typeB));
      }

      // Then by timestamp descending (newest first)
      final tsA = dataA['timestamp'];
      final tsB = dataB['timestamp'];
      DateTime? dateA, dateB;
      if (tsA is Timestamp) dateA = tsA.toDate();
      if (tsB is Timestamp) dateB = tsB.toDate();

      if (dateA != null && dateB != null) {
        final cmp = dateB.compareTo(dateA); // Descending!
        if (cmp != 0) return cmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      return _typePriority(typeA).compareTo(_typePriority(typeB));
    });
    return sorted;
  }

  static String _descriptionForEntry(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'deduction';
    final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
    final notes =
        (data['notes'] ?? data['description'] ?? '').toString().trim();

    String description = '';
    if (type == 'sale') {
      description = invoiceNumber.isNotEmpty
          ? 'فاتورة مبيعات رقم $invoiceNumber'
          : 'فاتورة مبيعات';
    } else if (type == 'sale_payment') {
      description = invoiceNumber.isNotEmpty
          ? 'سداد من فاتورة رقم $invoiceNumber'
          : 'سداد فاتورة';
    } else if (type == 'return') {
      description = invoiceNumber.isNotEmpty
          ? 'مرتجع مبيعات رقم $invoiceNumber'
          : 'مرتجع مبيعات';
    } else if (type == 'return_payment') {
      description = invoiceNumber.isNotEmpty
          ? 'سداد مرتجع رقم $invoiceNumber'
          : 'سداد مرتجع';
    } else if (type == 'opening') {
      description = 'رصيد افتتاحي';
    } else if (type == 'addition') {
      description = 'إضافة رصيد';
    } else {
      description = 'خصم رصيد (سداد)';
    }
    if (notes.isNotEmpty) {
      description += ' ($notes)';
    }
    return description;
  }

  static bool _isIncreaseType(String type) {
    return type == 'sale' ||
        type == 'addition' ||
        type == 'opening' ||
        type == 'return_payment';
  }

  static Color _colorForType(String type, bool isIncrease) {
    if (type == 'opening') return Colors.blue.shade700;
    return isIncrease ? Colors.green.shade700 : Colors.red.shade700;
  }

  Future<void> _editEntry(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type']?.toString() ?? 'deduction';
    final invoiceId = data['invoiceId']?.toString() ?? '';
    final currentAmount = (data['enteredBalance'] as num?)?.toDouble() ?? 0.0;
    final currentNotes = (data['notes'] ?? '').toString();

    final amountCtrl =
        TextEditingController(text: currentAmount.toStringAsFixed(2));
    final notesCtrl = TextEditingController(text: currentNotes);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xffead1ac),
          title: const Text('تعديل السجل',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final newAmount = double.tryParse(amountCtrl.text) ?? currentAmount;
    final newNotes = notesCtrl.text.trim();
    if ((newAmount - currentAmount).abs() < 0.001 &&
        newNotes == currentNotes.trim()) {
      return; // No changes
    }

    setState(() => _isBusy = true);
    try {
      final diff = newAmount - currentAmount;
      final batch = FirebaseFirestore.instance.batch();

      // Update history doc
      batch.update(doc.reference, {
        'enteredBalance': newAmount,
        'notes': newNotes,
      });

      double boxDelta = 0.0;
      String boxChangeName = '';
      String boxChangeNotes = '';

      if (type == 'addition') {
        boxDelta = -diff;
        boxChangeName = 'تعديل إضافة رصيد للعميل';
        boxChangeNotes = 'تعديل من $currentAmount إلى $newAmount ($newNotes)';
      } else if (type == 'deduction') {
        boxDelta = diff;
        boxChangeName = 'تعديل خصم رصيد للعميل';
        boxChangeNotes = 'تعديل من $currentAmount إلى $newAmount ($newNotes)';
      } else if (type == 'sale_payment') {
        boxDelta = diff;
        boxChangeName = 'تعديل سداد فاتورة رقم ${data['invoiceNumber']}';
        boxChangeNotes = 'تعديل سداد من $currentAmount إلى $newAmount';

        if (invoiceId.isNotEmpty) {
          final clientInvRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('invoices')
              .doc(invoiceId);
          batch.update(clientInvRef, {'paidAmount': newAmount});

          final rootInvRef =
              FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
          batch.update(rootInvRef, {'paidAmount': newAmount});
        }
      } else if (type == 'return_payment') {
        boxDelta = -diff;
        boxChangeName = 'تعديل سداد مرتجع رقم ${data['invoiceNumber']}';
        boxChangeNotes = 'تعديل سداد من $currentAmount إلى $newAmount';

        if (invoiceId.isNotEmpty) {
          final clientRetRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(clientRetRef, {'paidAmount': newAmount});

          final rootRetRef = FirebaseFirestore.instance
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(rootRetRef, {'paidAmount': newAmount});
        }
      } else if (type == 'sale') {
        if (invoiceId.isNotEmpty) {
          final clientInvRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('invoices')
              .doc(invoiceId);
          batch.update(clientInvRef, {'totalSum': newAmount});

          final rootInvRef =
              FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
          batch.update(rootInvRef, {'totalSum': newAmount});
        }
      } else if (type == 'return') {
        if (invoiceId.isNotEmpty) {
          final clientRetRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(clientRetRef, {'totalSum': newAmount});

          final rootRetRef = FirebaseFirestore.instance
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(rootRetRef, {'totalSum': newAmount});
        }
      }

      await batch.commit();

      if (boxDelta.abs() > 0.001) {
        final boxDocRef =
            FirebaseFirestore.instance.collection('box').doc('mainBox');
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final boxSnapshot = await transaction.get(boxDocRef);
          if (boxSnapshot.exists) {
            double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
            transaction
                .update(boxDocRef, {'value': currentBoxValue + boxDelta});
          }
        });

        await boxDocRef.collection('changes').add({
          'date': FieldValue.serverTimestamp(),
          'value': diff.abs(),
          'type': boxDelta >= 0 ? 'addition' : 'subtraction',
          'name': boxChangeName,
          'notes': boxChangeNotes,
        });
      }

      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تعديل السجل وإعادة حساب الرصيد')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteEntry(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type']?.toString() ?? 'deduction';
    final invoiceId = data['invoiceId']?.toString() ?? '';
    final enteredBalance = (data['enteredBalance'] as num?)?.toDouble() ?? 0.0;
    final desc = _descriptionForEntry(data);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content:
              Text('هل أنت متأكد من حذف "$desc"؟\nسيتم إعادة حساب الرصيد.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final batch = FirebaseFirestore.instance.batch();

      // Delete history doc
      batch.delete(doc.reference);

      double boxDelta = 0.0;
      String boxChangeName = '';
      String boxChangeNotes = '';

      if (type == 'addition') {
        boxDelta = enteredBalance;
        boxChangeName = 'حذف إضافة رصيد للعميل';
        boxChangeNotes = 'حذف سجل بقيمة $enteredBalance';
      } else if (type == 'deduction') {
        boxDelta = -enteredBalance;
        boxChangeName = 'حذف خصم رصيد للعميل';
        boxChangeNotes = 'حذف سجل بقيمة $enteredBalance';
      } else if (type == 'sale_payment') {
        boxDelta = -enteredBalance;
        boxChangeName = 'حذف سداد فاتورة رقم ${data['invoiceNumber']}';
        boxChangeNotes = 'حذف سداد بقيمة $enteredBalance';

        if (invoiceId.isNotEmpty) {
          final clientInvRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('invoices')
              .doc(invoiceId);
          batch.update(clientInvRef, {'paidAmount': 0.0});

          final rootInvRef =
              FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
          batch.update(rootInvRef, {'paidAmount': 0.0});
        }
      } else if (type == 'return_payment') {
        boxDelta = enteredBalance;
        boxChangeName = 'حذف سداد مرتجع رقم ${data['invoiceNumber']}';
        boxChangeNotes = 'حذف سداد بقيمة $enteredBalance';

        if (invoiceId.isNotEmpty) {
          final clientRetRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(clientRetRef, {'paidAmount': 0.0});

          final rootRetRef = FirebaseFirestore.instance
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.update(rootRetRef, {'paidAmount': 0.0});
        }
      } else if (type == 'sale') {
        if (invoiceId.isNotEmpty) {
          final clientInvRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('invoices')
              .doc(invoiceId);
          final clientInvSnap = await clientInvRef.get();
          if (clientInvSnap.exists) {
            final products = List<Map<String, dynamic>>.from(
                clientInvSnap.data()?['products'] ?? []);
            for (var product in products) {
              final name = product['product']?.toString() ?? '';
              if (name.isEmpty) continue;
              final amount =
                  double.tryParse(product['amount']?.toString() ?? '0') ?? 0.0;
              if (amount <= 0) continue;

              final q = await FirebaseFirestore.instance
                  .collection('products')
                  .where('name', isEqualTo: name)
                  .get();
              for (var pDoc in q.docs) {
                double qty = (pDoc['quantity'] as num?)?.toDouble() ?? 0.0;
                batch.update(pDoc.reference, {'quantity': qty + amount});
                batch.set(pDoc.reference.collection('changes').doc(), {
                  'date': DateTime.now(),
                  'amount': amount,
                  'type': 'increase',
                });
              }
            }
            batch.delete(clientInvRef);
          }

          final rootInvRef =
              FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
          batch.delete(rootInvRef);
        }
      } else if (type == 'return') {
        if (invoiceId.isNotEmpty) {
          final clientRetRef = FirebaseFirestore.instance
              .collection('clients')
              .doc(widget.clientId)
              .collection('returnInvoices')
              .doc(invoiceId);
          final clientRetSnap = await clientRetRef.get();
          if (clientRetSnap.exists) {
            final products = List<Map<String, dynamic>>.from(
                clientRetSnap.data()?['products'] ?? []);
            for (var product in products) {
              final name = product['product']?.toString() ?? '';
              if (name.isEmpty) continue;
              final amount =
                  double.tryParse(product['amount']?.toString() ?? '0') ?? 0.0;
              if (amount <= 0) continue;

              final q = await FirebaseFirestore.instance
                  .collection('products')
                  .where('name', isEqualTo: name)
                  .get();
              for (var pDoc in q.docs) {
                double qty = (pDoc['quantity'] as num?)?.toDouble() ?? 0.0;
                batch.update(pDoc.reference, {'quantity': qty - amount});
                batch.set(pDoc.reference.collection('changes').doc(), {
                  'date': DateTime.now(),
                  'amount': amount,
                  'type': 'decrease',
                });
              }
            }
            batch.delete(clientRetRef);
          }

          final rootRetRef = FirebaseFirestore.instance
              .collection('returnInvoices')
              .doc(invoiceId);
          batch.delete(rootRetRef);
        }
      }

      await batch.commit();

      if (boxDelta.abs() > 0.001) {
        final boxDocRef =
            FirebaseFirestore.instance.collection('box').doc('mainBox');
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final boxSnapshot = await transaction.get(boxDocRef);
          if (boxSnapshot.exists) {
            double currentBoxValue = (boxSnapshot['value'] ?? 0.0).toDouble();
            transaction
                .update(boxDocRef, {'value': currentBoxValue + boxDelta});
          }
        });

        await boxDocRef.collection('changes').add({
          'date': FieldValue.serverTimestamp(),
          'value': enteredBalance,
          'type': boxDelta >= 0 ? 'addition' : 'subtraction',
          'name': boxChangeName,
          'notes': boxChangeNotes,
        });
      }

      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف السجل وإعادة حساب الرصيد')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('تاريخ الرصيد'),
            backgroundColor: Colors.black.withOpacity(0.7),
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('clients')
                .doc(widget.clientId)
                .collection('balanceHistory')
                .orderBy('timestamp')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                    child: CircularProgressIndicator(
                        color: Colors.orange.shade700));
              }

              final sorted = _sortDocs(snapshot.data!.docs);

              if (sorted.isEmpty) {
                return const Center(
                    child:
                        Text('لا يوجد سجلات', style: TextStyle(fontSize: 16)));
              }

              return Directionality(
                textDirection: TextDirection.rtl,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.grey.shade300,
                          ),
                          child: DataTable(
                            headingRowColor:
                                MaterialStateProperty.all(Colors.black87),
                            headingTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            dataRowMaxHeight: 52,
                            dataRowMinHeight: 44,
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(
                                label: SizedBox(
                                  width: 150,
                                  child: Text('البيان',
                                      textAlign: TextAlign.right),
                                ),
                              ),
                              DataColumn(
                                label:
                                    Text('الحركة', textAlign: TextAlign.right),
                              ),
                              DataColumn(
                                label: Text('الرصيد قبل',
                                    textAlign: TextAlign.right),
                              ),
                              DataColumn(
                                label: Text('الرصيد بعد',
                                    textAlign: TextAlign.right),
                              ),
                              DataColumn(
                                label:
                                    Text('التاريخ', textAlign: TextAlign.right),
                              ),
                              DataColumn(
                                label:
                                    Text('إجراءات', textAlign: TextAlign.right),
                              ),
                            ],
                            rows: sorted.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final type =
                                  data['type']?.toString() ?? 'deduction';
                              final entered = (data['enteredBalance'] as num?)
                                      ?.toDouble() ??
                                  0.0;
                              final before =
                                  (data['balanceBefore'] as num?)?.toDouble() ??
                                      0.0;
                              final isIncrease = _isIncreaseType(type);
                              final after = isIncrease
                                  ? before + entered
                                  : before - entered;
                              final sign = isIncrease ? '+' : '-';
                              final color = _colorForType(type, isIncrease);
                              final description = _descriptionForEntry(data);

                              final timestamp = data['timestamp'] != null
                                  ? (data['timestamp'] as Timestamp).toDate()
                                  : DateTime.now();
                              final formattedDate =
                                  intl.DateFormat('yyyy-MM-dd hh:mm a')
                                      .format(timestamp);

                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        description,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Colors.grey.shade800,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '$sign${entered.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      before.toStringAsFixed(2),
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      after.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formattedDate,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined,
                                              color: Colors.blue.shade700,
                                              size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'تعديل',
                                          onPressed: _isBusy
                                              ? null
                                              : () => _editEntry(doc),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline,
                                              color: Colors.red.shade700,
                                              size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: 'حذف',
                                          onPressed: _isBusy
                                              ? null
                                              : () => _deleteEntry(doc),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isBusy)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Unified list entry (invoice / return invoice / payment card)
// ──────────────────────────────────────────────────────────────
enum _EntryKind { invoice, returnInvoice, payment }

class _InvoiceEntry {
  final QueryDocumentSnapshot doc;
  final _EntryKind kind;

  _InvoiceEntry({required this.doc, required this.kind});

  bool get isReturn => kind == _EntryKind.returnInvoice;

  Map<String, dynamic> get data => doc.data() as Map<String, dynamic>;
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
          color:
              selected ? Colors.orange.withOpacity(0.85) : Colors.grey.shade200,
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
