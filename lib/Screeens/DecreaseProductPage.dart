import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'DecreaseProductComponents/product_model.dart';
import 'DecreaseProductComponents/decrease_product_widgets.dart';
import 'DecreaseProductComponents/invoice_product_sheet.dart';
import 'DecreaseProductComponents/invoice_checkout_sheet.dart';
import 'DecreaseProductComponents/client_selection_dialog.dart';
import 'DecreaseProductComponents/calculator_dialog.dart';
import 'DecreaseProductComponents/bloc/invoice_cubit.dart';
import 'DecreaseProductComponents/bloc/invoice_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'Invoices/All_invoices.dart';
import 'Invoices/InvoiceDetailPage.dart';
import 'Data/quick_add_product_sheet.dart';
import '../Services/client_invoice_balance_sync_service.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/invoice_number_utils.dart';
import '../Services/return_invoice_save_service.dart';
import '../Services/invoice_stock_service.dart';
import '../Services/sales_invoice_actions_service.dart';
import '../Services/sales_invoice_update_service.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import '../repositories/payment_breakdown_repository.dart';
import '../Widgets/egypt_phone_field.dart';
import '../EditProductPage.dart';
import 'g_Nav.dart';
import '../Widgets/app_bar_navigation.dart';
import 'home_page.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../local_db/models/balance_history_local.dart';
import '../local_db/hive_init.dart';

class DecreaseProductPage extends StatefulWidget {
  /// When true, saves as [returnInvoices] (stock in, reversed profit/sales/box).
  final bool isReturnInvoice;

  /// When true, saves as a price quote (`price_quotes` collection).
  /// No stock/balance/box changes are applied until the user executes the quote.
  final bool isQuote;

  /// Pre-filled invoice for edit mode (sales only). Use [id] or [invoiceId] as root doc id.
  final Map<String, dynamic>? invoiceToEdit;

  const DecreaseProductPage({
    super.key,
    this.isReturnInvoice = false,
    this.isQuote = false,
    this.invoiceToEdit,
  });

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
  String get _pageTitle {
    if (widget.isQuote) {
      return _isEditing ? 'تعديل عرض سعر' : 'عرض سعر';
    }
    if (_isEditing && _editingInvoiceNumber != null) {
      return 'تعديل فاتورة #$_editingInvoiceNumber';
    }
    return widget.isReturnInvoice ? 'فواتير المرتجع' : 'المبيعات';
  }

  bool get _isEditing =>
      !widget.isReturnInvoice &&
      _editingRootInvoiceId != null &&
      _editingRootInvoiceId!.isNotEmpty;

  String get _mainCollection =>
      widget.isReturnInvoice ? 'returnInvoices' : 'invoices';

  String get _clientInvoiceSubcollection =>
      widget.isReturnInvoice ? 'returnInvoices' : 'invoices';

  final List<Product> _products = [];
  DateTime? _selectedDate;

  final List<Map<String, dynamic>> _addedProducts = [];
  int _lineIdCounter = 0;
  final TextEditingController _dateController = TextEditingController();
  bool _dataModified = false;
  bool _isSaving = false;
  bool _isFetching = true;
  double _clientBalance = 0.0;
  TextEditingController _clientNameController = TextEditingController();
  TextEditingController _productController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _newClientNameController =
      TextEditingController();
  List<String> _clients = [];
  int _defaultPriceTier = 1;
  bool _barcodeExternal = false;

  /// When true, search lists قطاعي (retail) products only.
  /// When false (normal), retail products are hidden from search.
  bool _retailOnlyMode = false;
  Map<String, dynamic>? _lastInvoice;
  String? _editingRootInvoiceId;
  String? _editingClientSubDocId;
  String _editingSourceCollection = 'invoices';
  Map<String, dynamic>? _originalInvoice;
  dynamic _editingInvoiceNumber;
  String _editingPaymentMethod = 'نقداً';
  String _editingNotes = '';
  double _editingInvoiceDiscountAmount = 0.0;
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
    double? selectedClientBalance;
    bool loadingClientBalance = false;
    bool addingNewClient = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> loadDialogClientBalance(String clientName) async {
            if (clientName.trim().isEmpty) {
              setSheet(() {
                selectedClientBalance = null;
                loadingClientBalance = false;
              });
              return;
            }
            setSheet(() {
              loadingClientBalance = true;
              selectedClientBalance = null;
            });
            final bal = await _fetchClientBalance(clientName.trim());
            setSheet(() {
              selectedClientBalance = bal;
              loadingClientBalance = false;
            });
          }

          if (selectedClient.isNotEmpty &&
              selectedClientBalance == null &&
              !loadingClientBalance) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadDialogClientBalance(selectedClient);
            });
          }
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
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.black54),
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
                              color:
                                  showAddField ? Colors.white : Colors.black87,
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
                        hintText: 'اسم العميل الجديد *',
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: 'الرصيد الافتتاحي (اختياري)',
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
                      hintText: '1xxxxxxxxx (اختياري)',
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
                        onPressed: addingNewClient
                            ? null
                            : () async {
                                final newName = newClientCtrl.text.trim();
                                if (newName.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('يرجى إدخال اسم العميل'),
                                    ),
                                  );
                                  return;
                                }
                                final phoneText =
                                    newClientPhoneCtrl.text.trim();
                                if (phoneText.isNotEmpty &&
                                    !EgyptPhoneField.isValidLocalPart(
                                        phoneText)) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'يرجى إدخال رقم هاتف صحيح بعد +20'),
                                    ),
                                  );
                                  return;
                                }
                                final alreadyExists = _clients.any((c) =>
                                    c.toLowerCase() == newName.toLowerCase());
                                if (alreadyExists) {
                                  setSheet(() {
                                    duplicateWarning =
                                        'هذا العميل موجود بالفعل';
                                    selectedClient = _clients.firstWhere((c) =>
                                        c.toLowerCase() ==
                                        newName.toLowerCase());
                                  });
                                  return;
                                }

                                setSheet(() {
                                  addingNewClient = true;
                                  duplicateWarning = null;
                                });
                                try {
                                  final balanceText =
                                      newClientBalanceCtrl.text.trim();
                                  final balance = balanceText.isEmpty
                                      ? 0.0
                                      : (double.tryParse(balanceText) ?? 0.0);
                                  final phone = phoneText.isEmpty
                                      ? ''
                                      : EgyptPhoneField.toWhatsappDigits(
                                          phoneText);
                                  final docRef = FirebaseFirestore.instance
                                      .collection('clients')
                                      .doc();
                                  final clientId = docRef.id;
                                  await docRef.set({
                                    'clientName': newName,
                                    'balance': balance,
                                    'phone': phone,
                                    'id': clientId,
                                  }, SetOptions(merge: true));
                                  if (balance != 0) {
                                    await docRef
                                        .collection('balanceHistory')
                                        .add({
                                      'enteredBalance': balance,
                                      'balanceBefore': 0.0,
                                      'type': 'opening',
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                                  }

                                  if (!ctx.mounted) return;
                                  setSheet(() {
                                    _clients.insert(0, newName);
                                    selectedClient = newName;
                                    selectedClientBalance = balance;
                                    showAddField = false;
                                    newClientCtrl.clear();
                                    newClientBalanceCtrl.clear();
                                    newClientPhoneCtrl.clear();
                                  });
                                  if (!mounted) return;
                                  setState(() {
                                    _clientBalance = balance;
                                  });
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('خطأ أثناء إضافة العميل: $e'),
                                    ),
                                  );
                                } finally {
                                  if (ctx.mounted) {
                                    setSheet(() => addingNewClient = false);
                                  }
                                }
                              },
                        child: addingNewClient
                            ? SizedBox(
                                width: 22.w,
                                height: 22.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('إضافة العميل',
                                style: TextStyle(fontSize: 13.sp)),
                      ),
                    ),
                  ],
                  // ── Duplicate warning ──
                  if (duplicateWarning != null) ...[
                    SizedBox(height: 8.h),
                    Container(
                      width: double.infinity,
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8.r),
                        border:
                            Border.all(color: Colors.orange.shade300, width: 1),
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
                                  fontSize: 13.sp, color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final client = filtered[i];
                              final isSelected = client == selectedClient;
                              return InkWell(
                                onTap: () {
                                  setSheet(() => selectedClient = client);
                                  loadDialogClientBalance(client);
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
                                            size: 18.sp, color: Colors.orange),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Divider(height: 20.h),

                  if (selectedClient.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10.r),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: loadingClientBalance
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
                          : Text(
                              'الرصيد الحالي: ${invoiceAmount(selectedClientBalance ?? 0)} ج.م',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                                color: (selectedClientBalance ?? 0) > 0
                                    ? Colors.red.shade700
                                    : Colors.black87,
                              ),
                            ),
                    ),
                    SizedBox(height: 12.h),
                  ],

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
                      prefixIcon: const Icon(Icons.payments_outlined,
                          color: Colors.black54),
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
                          : () async {
                              final bal = await _fetchClientBalance(
                                selectedClient.trim(),
                              );
                              if (!mounted) return;
                              setState(() {
                                _clientNameController.text = selectedClient;
                                _paidAmountController.text = localPaidCtrl.text;
                                _clientBalance = bal;
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

  void _applyInvoiceToEdit(Map<String, dynamic> inv) {
    _editingRootInvoiceId = SalesInvoiceActionsService.rootInvoiceIdFrom(inv);
    _editingClientSubDocId = inv['_clientSubDocId']?.toString();
    _editingSourceCollection =
        inv['_sourceCollection']?.toString() ?? 'invoices';
    _originalInvoice = Map<String, dynamic>.from(inv);
    _editingInvoiceNumber = inv['invoiceNumber'];

    _clientNameController.text = inv['clientName']?.toString() ?? '';
    _paidAmountController.text =
        invoiceNum(inv['paidAmount']).toStringAsFixed(2);
    _clientBalance = invoiceNum(inv['previousBalance']);

    final date = inv['date'];
    if (date is Timestamp) {
      _selectedDate = date.toDate();
    } else if (date is DateTime) {
      _selectedDate = date;
    } else {
      _selectedDate = DateTime.now();
    }
    _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];

    _addedProducts.clear();
    final products = inv['products'] as List<dynamic>? ?? [];
    for (final p in products) {
      _addedProducts.add(Map<String, dynamic>.from(p as Map));
    }
    _ensureAllLineIds();

    _editingPaymentMethod = inv['paymentMethod']?.toString() ?? 'نقداً';
    _editingNotes = inv['notes']?.toString() ?? '';
    _editingInvoiceDiscountAmount = invoiceNum(inv['invoiceDiscount']);
    _dataModified = true;
  }

  Timer? _productsDebounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchClients();
    productsBox.listenable().addListener(_onProductsBoxChanged);
    if (widget.invoiceToEdit != null) {
      _applyInvoiceToEdit(widget.invoiceToEdit!);
    } else {
      _selectedDate = DateTime.now();
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
    }
  }

  void _onProductsBoxChanged() {
    _productsDebounceTimer?.cancel();
    _productsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadProductsFromLocalCache();
      }
    });
  }

  @override
  void dispose() {
    _productsDebounceTimer?.cancel();
    productsBox.listenable().removeListener(_onProductsBoxChanged);
    super.dispose();
  }

  Map<String, ResolvedInvoiceProduct> get _productCatalog =>
      InvoiceStockService.memoryCatalogFromMaps(
        _products.map((p) => p.toMap()),
      );

  Future<double> _calculateTotalCost() async {
    final catalog = await InvoiceStockService.resolveCatalogIfNeeded(
      lines: _addedProducts,
      seed: _productCatalog,
    );
    return InvoiceStockService.computeCostTotal(_addedProducts, catalog);
  }

  double _calculateTotalSum() {
    return _addedProducts.fold(0.0, (sum, product) => sum + product['total']);
  }

  void _assignLineId(Map<String, dynamic> entry) {
    entry.putIfAbsent('lineId', () => _lineIdCounter++);
  }

  void _ensureAllLineIds() {
    for (final p in _addedProducts) {
      _assignLineId(p);
    }
    for (final p in _addedProducts) {
      final id = p['lineId'];
      if (id is int && id >= _lineIdCounter) {
        _lineIdCounter = id + 1;
      }
    }
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

  Future<void> _confirmRemoveInvoiceLine(int index) async {
    if (index < 0 || index >= _addedProducts.length) return;
    final productName = invoiceProductName(_addedProducts[index]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف'),
        content: Text('هل تريد حذف "$productName" من الفاتورة؟'),
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
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _addedProducts.removeAt(index);
      _dataModified = true;
    });
  }

  void _moveInvoiceLineUp(int index) {
    if (index <= 0) return;
    _reorderAddedProducts(index, index - 1);
  }

  void _moveInvoiceLineDown(int index) {
    if (index >= _addedProducts.length - 1) return;
    _reorderAddedProducts(index, index + 2);
  }

  void _showReorderInvoiceLineSheet(int index) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('تحريك لأعلى'),
              enabled: index > 0,
              onTap: index > 0
                  ? () {
                      Navigator.pop(sheetContext);
                      _moveInvoiceLineUp(index);
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('تحريك لأسفل'),
              enabled: index < _addedProducts.length - 1,
              onTap: index < _addedProducts.length - 1
                  ? () {
                      Navigator.pop(sheetContext);
                      _moveInvoiceLineDown(index);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchProducts() async {
    // Load from Hive local cache immediately (0ms wait).
    // RealtimeSyncService automatically updates local Hive storage in the background.
    _loadProductsFromLocalCache();
  }

  /// Loads products from Hive local cache (used when offline or on error).
  void _loadProductsFromLocalCache() {
    if (!mounted) return;
    final locals = ProductRepository.instance.getAll();
    setState(() {
      _products
        ..clear()
        ..addAll(locals.map((p) => Product(
              id: p.id,
              randomNumber: 0,
              name: p.name,
              description: p.description,
              sellingPrice1: p.sellingPrice1,
              sellingPrice2: p.sellingPrice2,
              sellingPrice3: p.sellingPrice3,
              costPrice: p.costPrice,
              quantity: p.quantity,
              alertAmount: 0,
              retail: p.retail,
            )));
      _isFetching = false;
    });
  }

  Iterable<Product> _productsMatchingSearch(String query) {
    if (query.isEmpty) return const Iterable<Product>.empty();
    final q = query.toLowerCase();
    Iterable<Product> list = _products.where(
      (p) => p.name.toLowerCase().contains(q),
    );
    if (_retailOnlyMode) {
      list = list.where((p) => p.retail);
    } else {
      list = list.where((p) => !p.retail);
    }
    return list;
  }

  Future<void> _addNewProductInline({String? initialName}) async {
    final result = await showQuickAddProductSheet(
      context,
      initialName: initialName,
      showRetailOption: !widget.isReturnInvoice,
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

  void _toggleRetailOnlyMode() {
    setState(() {
      _retailOnlyMode = !_retailOnlyMode;
    });
    if (_retailOnlyMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('وضع قطاعي: يمكن إضافة منتجات قطاعي فقط للفاتورة'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchClients() async {
    // 1. Immediately load from Hive primary database (0ms wait)
    _loadClientsFromLocalCache();

    // 2. Background delta-sync if online
    if (ConnectivityService.instance.isOnline) {
      ClientRepository.instance.deltaSync().then((_) {
        if (mounted) _loadClientsFromLocalCache();
      }).catchError((_) {});
    }
  }

  /// Loads client names from Hive local cache.
  void _loadClientsFromLocalCache() {
    if (!mounted) return;
    final locals = ClientRepository.instance.getAll();
    final names =
        locals.map((c) => c.name.trim()).where((n) => n.isNotEmpty).toList();
    if (mounted) {
      setState(() {
        _clients = names;
      });
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
    if (picked != null && mounted) {
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
    if (_isSaving) return;
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

    if (!_dataModified && !_isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ البيانات بالفعل')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? resolvedClientId;
      if (effectiveClient.isNotEmpty) {
        // ALWAYS use Hive local cache to resolve client ID instantly
        final localClient =
            ClientRepository.instance.findByName(effectiveClient);
        if (localClient != null) {
          resolvedClientId = localClient.id;
        } else {
          // New client: Generate ID and save locally first
          resolvedClientId =
              FirebaseFirestore.instance.collection('clients').doc().id;
          final clientData = {
            'clientName': effectiveClient,
            'balance': 0.0,
            'id': resolvedClientId,
          };

          await ClientRepository.instance
              .upsertLocal(resolvedClientId, clientData);

          // Background sync to Firestore without blocking the UI
          FirebaseFirestore.instance
              .collection('clients')
              .doc(resolvedClientId)
              .set(clientData, SetOptions(merge: true))
              .catchError((_) {});
        }
      }

      if (widget.isQuote) {
        // ── Quote mode: save to price_quotes, no stock/balance/box changes ──
        final totalSum = _calculateTotalSum();
        final effectiveDiscountAmt = discountIsPercent
            ? totalSum * invoiceDiscount / 100
            : invoiceDiscount;
        final totalSumFinal = totalSum - effectiveDiscountAmt;

        // Use the already-resolved client ID from above
        final resolvedClientIdForQuote = resolvedClientId ?? '';

        final docId = (_editingRootInvoiceId != null &&
                _editingRootInvoiceId!.isNotEmpty)
            ? _editingRootInvoiceId!
            : FirebaseFirestore.instance.collection('price_quotes').doc().id;

        final quoteData = <String, dynamic>{
          'id': docId,
          'clientName': effectiveClient,
          'clientId': resolvedClientIdForQuote,
          'date': _selectedDate?.toIso8601String(),
          'totalSum': totalSumFinal,
          'paidAmount': effectivePaid,
          'balance': totalSumFinal - effectivePaid,
          'previousBalance': _clientBalance,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'invoiceDiscount': effectiveDiscountAmt,
          'discountIsPercent': false,
          'products': List<Map<String, dynamic>>.from(_addedProducts),
        };

        // Always enqueue for reliable sync (works both online and offline)
        await SyncQueueManager.instance.enqueue(
          operationType: 'createQuote',
          payload: {
            'quoteId': docId,
            'quoteData': {
              ...quoteData,
              'date': _selectedDate?.toIso8601String(),
              'createdAt': _originalInvoice?['createdAt']?.toString() ??
                  DateTime.now().toIso8601String(),
            },
          },
        );
        // Background sync to Firestore without blocking the UI
        ConnectivityService.instance.forceSync();

        _lastInvoice = Map<String, dynamic>.from(quoteData);
      } else if (_isEditing &&
          _originalInvoice != null &&
          _editingRootInvoiceId != null) {
        final totalSumBeforeDiscount = _calculateTotalSum();
        // Run in background — updateSalesInvoice writes Hive first then enqueues.
        // UI is unblocked immediately regardless of connectivity.
        SalesInvoiceUpdateService.updateSalesInvoice(
          rootInvoiceId: _editingRootInvoiceId!,
          clientSubInvoiceDocId: _editingClientSubDocId,
          originalInvoice: _originalInvoice!,
          newProducts: List<Map<String, dynamic>>.from(_addedProducts),
          clientName: effectiveClient,
          selectedDate: _selectedDate,
          paidAmount: effectivePaid,
          paymentMethod: paymentMethod,
          notes: notes,
          invoiceDiscount: invoiceDiscount,
          discountIsPercent: discountIsPercent,
          totalSumBeforeDiscount: totalSumBeforeDiscount,
          sourceCollection: _editingSourceCollection,
        ).catchError((_) {});

        final effectiveDiscountAmt = discountIsPercent
            ? totalSumBeforeDiscount * invoiceDiscount / 100
            : invoiceDiscount;
        final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;
        final totalCost = InvoiceStockService.computeCostTotal(
          List<Map<String, dynamic>>.from(_addedProducts),
          _productCatalog,
        );
        final balance = totalSumFinal - effectivePaid;

        _lastInvoice = {
          ..._originalInvoice!,
          'id': _editingRootInvoiceId,
          'clientName': effectiveClient,
          'date': _selectedDate,
          'totalSum': totalSumFinal,
          'profitMargin': totalSumFinal - totalCost,
          'paidAmount': effectivePaid,
          'balance': balance,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'invoiceDiscount': effectiveDiscountAmt,
          'products': List<Map<String, dynamic>>.from(_addedProducts),
        };
      } else if (widget.isReturnInvoice) {
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
          productCatalog: _productCatalog,
        );
      } else {
        final totalSum = _calculateTotalSum();
        final effectiveDiscountAmt = discountIsPercent
            ? totalSum * invoiceDiscount / 100
            : invoiceDiscount;

        final totalSumFinal = totalSum - effectiveDiscountAmt;
        final catalogSeed = _productCatalog;
        final lines = List<Map<String, dynamic>>.from(_addedProducts);

        final newInvoiceNumber = await _fetchNextInvoiceNumber();
        final catalog = await InvoiceStockService.resolveCatalogIfNeeded(
          lines: lines,
          seed: catalogSeed,
        );
        final existingBalance = _getClientBalanceSync(effectiveClient);

        final totalCost = InvoiceStockService.computeCostTotal(lines, catalog);
        final profitMargin = totalSumFinal - totalCost;
        final balance = totalSumFinal - effectivePaid;
        final updatedBalance = existingBalance + balance;

        final docRef =
            FirebaseFirestore.instance.collection(_mainCollection).doc();
        final invoiceData = <String, dynamic>{
          'id': docRef.id,
          'invoiceNumber': newInvoiceNumber,
          'clientName': effectiveClient,
          'clientId': resolvedClientId,
          'date': (_selectedDate ?? DateTime.now()).toIso8601String(),
          'totalSum': totalSumFinal,
          'profitMargin': profitMargin,
          'paidAmount': effectivePaid,
          'balance': balance,
          'previousBalance': existingBalance,
          'paymentMethod': paymentMethod,
          'notes': notes,
          'invoiceDiscount': effectiveDiscountAmt,
          'invoiceType': 'sale',
          'isSpecial': false,
          'products': lines,
        };

        _lastInvoice = Map<String, dynamic>.from(invoiceData);

        // 1. Write to local Hive primary database immediately (<10ms)
        await InvoiceRepository.instance
            .upsertSaleLocal(docRef.id, invoiceData);

        // 2. Update stock locally
        await InvoiceStockService.applyStockChanges(
          lines: lines,
          restore: false,
          changeDate: _selectedDate,
          catalog: catalog,
        );

        // 2. Save sales invoice locally in Hive so it appears instantly offline
        // (already saved above)

        // 3. Update client balance & balance history locally in Hive
        if (resolvedClientId != null && resolvedClientId.isNotEmpty) {
          await ClientRepository.instance
              .updateLocalBalance(resolvedClientId, updatedBalance);

          // Entry 1: Sales invoice total (debt increase)
          await BalanceHistoryRepository.instance.upsertLocal(
            BalanceHistoryLocal(
              id: '${docRef.id}_sale',
              parentId: resolvedClientId,
              parentType: 'client',
              enteredBalance: totalSumFinal,
              balanceBefore: existingBalance,
              type: 'sale',
              invoiceId: docRef.id,
              invoiceNumber: newInvoiceNumber.toString(),
              timestamp: _selectedDate ?? DateTime.now(),
            ),
          );

          // Entry 2: Payment received (debt decrease) if > 0
          if (effectivePaid > 0) {
            await BalanceHistoryRepository.instance.upsertLocal(
              BalanceHistoryLocal(
                id: '${docRef.id}_pay',
                parentId: resolvedClientId,
                parentType: 'client',
                enteredBalance: effectivePaid,
                balanceBefore: existingBalance + totalSumFinal,
                type: 'sale_payment',
                invoiceId: docRef.id,
                invoiceNumber: newInvoiceNumber.toString(),
                timestamp: _selectedDate ?? DateTime.now(),
              ),
            );
          }
        }

        // 4. Update cash box locally
        if (effectivePaid > 0) {
          await BoxRepository.instance.increment(effectivePaid);
        }

        // 5. Enqueue background sync to Firebase
        await SyncQueueManager.instance.enqueue(
          operationType: 'createInvoice',
          payload: {
            'clientId': resolvedClientId ?? docRef.id,
            'invoiceId': docRef.id,
            'invoiceData': invoiceData,
            'products': lines,
            'totalSum': totalSumFinal,
            'paidAmount': effectivePaid,
          },
        );

        // Trigger background sync without awaiting
        ConnectivityService.instance.forceSync();
      }

      if (!mounted) return;
      setState(() {
        _dataModified = false;
        _isSaving = false;
      });

      _showSaveSuccessDialog(_lastInvoice!);
    } catch (e) {
      if (!mounted) return;
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
      MaterialPageRoute(builder: (_) => const GNavPage()),
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
            widget.isQuote
                ? 'تم حفظ عرض السعر'
                : _isEditing
                    ? 'تم تعديل الفاتورة بنجاح'
                    : 'تم الحفظ بنجاح',
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
                        clientId: clientName.isNotEmpty ? clientName : null,
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
                      if (_isEditing && context.mounted) {
                        Navigator.of(context).pop(true);
                      } else {
                        _navigateHome();
                      }
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

  bool _clientNameInList(String clientName) {
    final normalized = clientName.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _clients.any((c) => c.trim().toLowerCase() == normalized);
  }

  Future<bool> _clientExists(String clientName) async {
    final name = clientName.trim();
    if (name.isEmpty) return false;
    if (_clientNameInList(name)) return true;

    // ALWAYS deal with Hive directly for instant offline/online check
    final local = ClientRepository.instance.findByName(name);
    return local != null;
  }

  /// Reads client balance synchronously from Hive local cache — instant, zero network.
  double _getClientBalanceSync(String clientName) {
    final name = clientName.trim();
    if (name.isEmpty) return 0.0;
    return ClientRepository.instance.findByName(name)?.balance ?? 0.0;
  }

  /// Async wrapper kept for compatibility with checkout sheet interface.
  Future<double> _fetchClientBalance(String clientName) async {
    return _getClientBalanceSync(clientName);
  }

  Future<int> _fetchNextInvoiceNumber() async {
    final type = widget.isReturnInvoice ? 'return' : 'sale';
    return LocalInvoiceCounter.nextNumber(type);
  }

  Future<void> _commitClientAndBoxWrites({
    required DocumentReference<Map<String, dynamic>> clientDocRef,
    required DocumentReference<Map<String, dynamic>> boxDocRef,
    required String effectiveClient,
    required double updatedBalance,
    required String invoiceId,
    required int newInvoiceNumber,
    required double totalSumFinal,
    required double effectivePaid,
    required double balance,
    required String paymentMethod,
    required String notes,
    required List<Map<String, dynamic>> products,
    required double existingBalance,
    required double invoiceDiscount,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      clientDocRef,
      {'clientName': effectiveClient, 'balance': updatedBalance},
      SetOptions(merge: true),
    );
    batch.set(clientDocRef.collection(_clientInvoiceSubcollection).doc(), {
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
      'date': _selectedDate,
      'totalSum': totalSumFinal,
      'paidAmount': effectivePaid,
      'balance': balance,
      'previousBalance': _clientBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': invoiceDiscount,
      'isSpecial': false,
      'products': products,
    });
    // Entry 1: Invoice total (debt increase)
    batch.set(
        clientDocRef.collection('balanceHistory').doc('${invoiceId}_sale'), {
      'enteredBalance': totalSumFinal,
      'balanceBefore': existingBalance,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'sale',
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
    });
    // Entry 2: Payment received (debt decrease) — only if > 0
    if (effectivePaid > 0) {
      batch.set(
          clientDocRef.collection('balanceHistory').doc('${invoiceId}_pay'), {
        'enteredBalance': effectivePaid,
        'balanceBefore': existingBalance + totalSumFinal,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'sale_payment',
        'invoiceId': invoiceId,
        'invoiceNumber': newInvoiceNumber,
      });
    }
    batch.set(
      boxDocRef,
      {'value': FieldValue.increment(effectivePaid)},
      SetOptions(merge: true),
    );
    batch.set(boxDocRef.collection('changes').doc(), {
      'date': FieldValue.serverTimestamp(),
      'value': effectivePaid,
      'type': 'addition',
      'name': effectiveClient,
      'invoiceNumber': newInvoiceNumber,
    });
    await batch.commit();
  }

  Future<void> _fetchAndSetClientBalance(String clientName) async {
    final bal = await _fetchClientBalance(clientName);
    if (!mounted) return;
    setState(() => _clientBalance = bal);
  }

  // ─────────────────────────────────────────────
  // Product bottom sheet  (add or edit)
  // ─────────────────────────────────────────────
  double _lineTotalForEntry(Map<String, dynamic> entry, double amount) {
    final price = (entry['selectedPrice'] as num).toDouble();
    final discount = (entry['discount'] ?? 0.0).toDouble();
    final isPercent = entry['discountIsPercent'] == true;
    final subtotal = price * amount;
    final result = isPercent
        ? subtotal - (subtotal * discount / 100)
        : subtotal - discount;
    return result < 0 ? 0 : result;
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

  String _getProductDescription(String name) {
    if (name.isEmpty) return '';
    final idx = _products.indexWhere((p) => p.name == name);
    if (idx < 0) return '';
    return _products[idx].description?.trim() ?? '';
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

  Future<String?> _resolveProductDocId(Product product) async {
    if (product.id.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(product.id)
          .get();
      if (doc.exists) return product.id;
    }
    final query = await FirebaseFirestore.instance
        .collection('products')
        .where('name', isEqualTo: product.name)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  Future<Product?> _refreshProductFromFirestore(
    String productId, {
    String? previousName,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .get();
    if (!doc.exists) return null;

    final data = Map<String, dynamic>.from(doc.data()!);
    data['id'] = doc.id;
    final updated = Product.fromMap(data);

    if (!mounted) return updated;

    setState(() {
      final idx = _products.indexWhere(
        (p) =>
            p.id == productId ||
            (previousName != null && p.name == previousName),
      );
      if (idx >= 0) {
        _products[idx] = updated;
      }

      final namesToMatch = <String>{
        updated.name,
        if (previousName != null && previousName.isNotEmpty) previousName,
      };
      for (var i = 0; i < _addedProducts.length; i++) {
        final lineName = _addedProducts[i]['product']?.toString() ?? '';
        if (!namesToMatch.contains(lineName)) continue;
        final line = Map<String, dynamic>.from(_addedProducts[i]);
        if (lineName != updated.name) {
          line['product'] = updated.name;
        }
        line['sellingPrice1'] = updated.sellingPrice1;
        line['sellingPrice2'] = updated.sellingPrice2;
        line['sellingPrice3'] = updated.sellingPrice3;
        line['quantity'] = updated.quantity;
        final amount = double.tryParse(line['amount'].toString()) ?? 0.0;
        line['total'] = _lineTotalForEntry(line, amount);
        _addedProducts[i] = line;
        _dataModified = true;
      }
    });

    return updated;
  }

  Future<Product?> _navigateToEditProduct(Product product) async {
    final productId = await _resolveProductDocId(product);
    if (productId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر العثور على المنتج')),
        );
      }
      return null;
    }

    final previousName = product.name;
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .get();
    if (!snap.exists || !mounted) return null;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProductPage(
          productId: productId,
          productData: snap.data()!,
        ),
      ),
    );

    if (!mounted) return null;
    return _refreshProductFromFirestore(
      productId,
      previousName: previousName,
    );
  }

  void _showProductSheet({int? editIndex, Product? newProduct}) {
    final Product product = editIndex != null
        ? (() {
            final item = _addedProducts[editIndex];
            final itemId =
                item['productId']?.toString() ?? item['id']?.toString();
            final itemName = item['product']?.toString();
            return _products.firstWhere(
              (p) => (itemId != null && p.id == itemId) || p.name == itemName,
              orElse: () => Product(
                id: itemId ?? '',
                randomNumber: 0,
                name: itemName ?? '',
                sellingPrice1: invoiceNum(item['sellingPrice1']),
                sellingPrice2: invoiceNum(item['sellingPrice2']),
                sellingPrice3: invoiceNum(item['sellingPrice3']),
                costPrice: invoiceNum(item['costPrice']),
                quantity: invoiceNum(item['quantity']),
                alertAmount: 0,
              ),
            );
          })()
        : newProduct!;

    var sheetProduct = product;

    double amount = editIndex != null
        ? double.tryParse(_addedProducts[editIndex]['amount'].toString()) ?? 1.0
        : 1.0;
    int priceTier = editIndex != null
        ? (_addedProducts[editIndex]['priceTier'] ?? 1)
        : _defaultPriceTier;
    double customPrice =
        editIndex != null && (_addedProducts[editIndex]['priceTier'] ?? 1) == 0
            ? ((_addedProducts[editIndex]['selectedPrice'] ?? 0.0) as num)
                .toDouble()
            : 0.0;
    double sp1 = editIndex != null
        ? invoiceNum(_addedProducts[editIndex]['sellingPrice1'])
        : product.sellingPrice1;
    double sp2 = editIndex != null
        ? invoiceNum(_addedProducts[editIndex]['sellingPrice2'])
        : product.sellingPrice2;
    double sp3 = editIndex != null
        ? invoiceNum(_addedProducts[editIndex]['sellingPrice3'])
        : product.sellingPrice3;
    if (sp1 == 0) sp1 = product.sellingPrice1;
    if (sp2 == 0) sp2 = product.sellingPrice2;
    if (sp3 == 0) sp3 = product.sellingPrice3;
    double discount = editIndex != null
        ? ((_addedProducts[editIndex]['discount'] ?? 0.0) as num).toDouble()
        : 0.0;
    bool discountIsPercent = editIndex != null
        ? (_addedProducts[editIndex]['discountIsPercent'] ?? true)
        : true;
    String barcodeNote = editIndex != null
        ? (_addedProducts[editIndex]['barcodeNote'] ?? '')
        : '';
    String customProductName = editIndex != null
        ? (_addedProducts[editIndex]['customProductName']?.toString() ?? '')
        : '';
    bool removeProduct = false;
    bool costObscured = false;

    final TextEditingController qtyCtrl =
        TextEditingController(text: amount.toStringAsFixed(1));
    final TextEditingController discountCtrl = TextEditingController(
        text: discount > 0 ? discount.toStringAsFixed(1) : '');
    final TextEditingController barcodeCtrl =
        TextEditingController(text: barcodeNote);
    final TextEditingController customNameCtrl =
        TextEditingController(text: customProductName);
    final TextEditingController customPriceCtrl = TextEditingController(
        text: customPrice > 0 ? customPrice.toStringAsFixed(2) : '');
    final TextEditingController sp1Ctrl =
        TextEditingController(text: sp1 > 0 ? sp1.toStringAsFixed(2) : '');
    final TextEditingController sp2Ctrl =
        TextEditingController(text: sp2 > 0 ? sp2.toStringAsFixed(2) : '');
    final TextEditingController sp3Ctrl =
        TextEditingController(text: sp3 > 0 ? sp3.toStringAsFixed(2) : '');

    double getPriceForTier(int tier) {
      if (tier == 0) return customPrice;
      switch (tier) {
        case 2:
          return sp2;
        case 3:
          return sp3;
        default:
          return sp1;
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
                    // Product name + open full edit page
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              sheetProduct.name,
                              style: TextStyle(
                                fontSize: 17.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final updated =
                                await _navigateToEditProduct(sheetProduct);
                            if (updated == null || !ctx.mounted) return;
                            setSheet(() {
                              sheetProduct = updated;
                              sp1 = updated.sellingPrice1;
                              sp2 = updated.sellingPrice2;
                              sp3 = updated.sellingPrice3;
                              sp1Ctrl.text =
                                  sp1 > 0 ? sp1.toStringAsFixed(2) : '';
                              sp2Ctrl.text =
                                  sp2 > 0 ? sp2.toStringAsFixed(2) : '';
                              sp3Ctrl.text =
                                  sp3 > 0 ? sp3.toStringAsFixed(2) : '';
                            });
                          },
                          icon: Icon(Icons.edit_outlined, size: 18.sp),
                          label: Text(
                            'تعديل المنتج',
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'اسم المخزن: ${sheetProduct.name}',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    if (sheetProduct.description != null &&
                        sheetProduct.description!.trim().isNotEmpty) ...[
                      SizedBox(height: 6.h),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16.sp, color: Colors.blue.shade800),
                                SizedBox(width: 6.w),
                                Text(
                                  'وصف المنتج (تلميح للاسترشاد فقط - لا يظهر بالفاتورة):',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 3.h),
                            Text(
                              sheetProduct.description!.trim(),
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 8.h),
                    TextField(
                      controller: customNameCtrl,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'اسم مخصص (للفاتورة فقط)',
                        hintText: 'اتركه فارغاً لاستخدام اسم المخزن',
                        hintStyle: TextStyle(fontSize: 11.sp),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 10.h,
                          horizontal: 12.w,
                        ),
                      ),
                      onTap: () => _selectAllField(customNameCtrl),
                      onChanged: (v) => customProductName = v,
                    ),
                    SizedBox(height: 14.h),

                    // ── سعر البيع ──
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: priceTier == 0
                            ? TextField(
                                controller: customPriceCtrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800),
                                decoration: InputDecoration(
                                  hintText: 'سعر خاص',
                                  hintStyle: TextStyle(
                                      fontSize: 12.sp, color: Colors.grey),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r),
                                      borderSide: const BorderSide(
                                          color: Colors.orange)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r),
                                      borderSide: const BorderSide(
                                          color: Colors.orange, width: 2)),
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 12.w),
                                ),
                                onTap: () => _selectAllField(customPriceCtrl),
                                onChanged: (v) => setSheet(() {
                                  customPrice = double.tryParse(v) ?? 0.0;
                                }),
                              )
                            : TextField(
                                controller: priceTier == 2
                                    ? sp2Ctrl
                                    : priceTier == 3
                                        ? sp3Ctrl
                                        : sp1Ctrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800),
                                decoration: InputDecoration(
                                  hintText: 'أدخل السعر',
                                  hintStyle: TextStyle(
                                      fontSize: 12.sp, color: Colors.grey),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r),
                                      borderSide: const BorderSide(
                                          color: Colors.orange)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.r),
                                      borderSide: const BorderSide(
                                          color: Colors.orange, width: 2)),
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 10.h, horizontal: 12.w),
                                ),
                                onTap: () => _selectAllField(
                                  priceTier == 2
                                      ? sp2Ctrl
                                      : priceTier == 3
                                          ? sp3Ctrl
                                          : sp1Ctrl,
                                ),
                                onChanged: (v) => setSheet(() {
                                  final parsed = double.tryParse(v) ?? 0.0;
                                  if (priceTier == 2) {
                                    sp2 = parsed;
                                  } else if (priceTier == 3) {
                                    sp3 = parsed;
                                  } else {
                                    sp1 = parsed;
                                  }
                                }),
                              ),
                      ),
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
                    SizedBox(height: 10.h),

                    // ── الكمية ──
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: _SheetValueBox(
                              value: calcTotal(amount, discount,
                                      discountIsPercent, priceTier)
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                            contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                          ),
                          onTap: () => _selectAllField(qtyCtrl),
                          onChanged: (v) => setSheet(
                              () => amount = double.tryParse(v) ?? amount),
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                          onChanged: (v) => setSheet(
                              () => discount = double.tryParse(v) ?? 0.0),
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
                          style: TextStyle(
                              fontSize: 11.sp, color: Colors.black54)),
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
                            suffixIcon: Icon(Icons.edit_outlined, size: 18.sp),
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
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                sheetProduct.quantity.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: 6.h),
                            GestureDetector(
                              onTap: () =>
                                  setSheet(() => costObscured = !costObscured),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 24.w, vertical: 8.h),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6.r),
                                  child: costObscured
                                      ? ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                              sigmaX: 8, sigmaY: 8),
                                          child: Text(
                                            sheetProduct.costPrice
                                                .toStringAsFixed(2),
                                            style: TextStyle(
                                              fontSize: 15.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          sheetProduct.costPrice
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
                          onPressed: () async {
                            if (removeProduct) {
                              Navigator.pop(ctx);
                              if (editIndex != null) {
                                setState(() {
                                  _addedProducts.removeAt(editIndex);
                                  _dataModified = true;
                                });
                              }
                              return;
                            }

                            double activePrice = 0.0;
                            if (priceTier == 0) {
                              activePrice = customPrice;
                            } else if (priceTier == 2) {
                              activePrice = sp2;
                            } else if (priceTier == 3) {
                              activePrice = sp3;
                            } else {
                              activePrice = sp1;
                            }

                            if (sheetProduct.costPrice > 0 &&
                                activePrice < sheetProduct.costPrice) {
                              final proceed = await showDialog<bool>(
                                context: context,
                                builder: (dialogCtx) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: const Text('تنبيه هام'),
                                    content: Text(
                                        'سعر البيع ($activePrice) أقل من سعر التكلفة (${sheetProduct.costPrice}). هل تريد الاستمرار؟'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogCtx, false),
                                        child: const Text('تعديل السعر',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green),
                                        onPressed: () =>
                                            Navigator.pop(dialogCtx, true),
                                        child: const Text('استمرار',
                                            style:
                                                TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              if (proceed != true) return;
                            }

                            if (!context.mounted) return;
                            Navigator.pop(ctx);
                            await _syncProductPricesToFirestore(
                              product: sheetProduct,
                              sp1: sp1,
                              sp2: sp2,
                              sp3: sp3,
                              sp1Text: sp1Ctrl.text,
                              sp2Text: sp2Ctrl.text,
                              sp3Text: sp3Ctrl.text,
                            );
                            if (!mounted) return;
                            double price = getPriceForTier(priceTier);
                            double total = calcTotal(
                                amount, discount, discountIsPercent, priceTier);
                            final entry = <String, dynamic>{
                              'product': sheetProduct.name,
                              'productId': sheetProduct.id,
                              'date': _selectedDate,
                              'amount': amount,
                              'costPrice': sheetProduct.costPrice,
                              'sellingPrice1': sp1,
                              'sellingPrice2': sp2,
                              'sellingPrice3': sp3,
                              'quantity': sheetProduct.quantity,
                              'selectedPrice':
                                  priceTier == 0 ? customPrice : price,
                              'priceTier': priceTier,
                              'total': total,
                              'discount': discount,
                              'discountIsPercent': discountIsPercent,
                              'barcodeNote': barcodeNote,
                            };
                            final trimmedCustomName = customProductName.trim();
                            if (trimmedCustomName.isNotEmpty) {
                              entry['customProductName'] = trimmedCustomName;
                            }
                            if (editIndex != null) {
                              final lineId =
                                  _addedProducts[editIndex]['lineId'];
                              if (lineId != null) entry['lineId'] = lineId;
                            }
                            setState(() {
                              if (editIndex != null) {
                                _addedProducts[editIndex] = entry;
                              } else {
                                int idx = _addedProducts.indexWhere((p) =>
                                    p['product'] == sheetProduct.name &&
                                    (p['customProductName']?.toString() ??
                                            '') ==
                                        trimmedCustomName);
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
                          child: Text(
                              widget.isQuote ? 'حفظ عرض السعر' : 'متابعة',
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
  void _showCheckoutSheet() async {
    if (_addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إضافة منتجات إلى الفاتورة')));
      return;
    }

    final result = await showInvoiceCheckoutSheet(
      context: context,
      isEditing: _isEditing,
      paymentMethod: _isEditing ? _editingPaymentMethod : 'نقداً',
      invoiceDiscount: _isEditing ? _editingInvoiceDiscountAmount : 0.0,
      clientName: _clientNameController.text,
      clientBalance: _clientBalance,
      notes: _isEditing ? _editingNotes : '',
      originalPaidAmount:
          _isEditing ? invoiceNum(_originalInvoice?['paidAmount']) : 0.0,
      totalSum: _calculateTotalSum(),
      clients: _clients,
      isReturnInvoice: widget.isReturnInvoice,
      isQuote: widget.isQuote,
      isSaving: _isSaving,
      clientExists: _clientExists,
      fetchClientBalance: _fetchClientBalance,
    );

    if (result != null && mounted) {
      if (result.walletAmount > 0 ||
          result.cashAmount > 0 ||
          result.instapayAmount > 0 ||
          result.bankTransferAmount > 0) {
        PaymentBreakdownRepository.instance.saveBreakdown(
          wallet: result.walletAmount,
          cash: result.cashAmount,
          instapay: result.instapayAmount,
          bankTransfer: result.bankTransferAmount,
          notes: result.notes,
          date: _selectedDate,
        );
      }

      // Sync read from Hive — instant, no await needed
      final bal = _getClientBalanceSync(result.clientName);
      setState(() {
        _clientBalance = bal;
        _clientNameController.text = result.clientName;
      });
      _saveData(
        clientName: result.clientName,
        paidAmount: result.paidAmount,
        paymentMethod: result.paymentMethod,
        notes: result.notes,
        invoiceDiscount: result.invoiceDiscount,
        discountIsPercent: result.discountIsPercent,
      );
    }
  }

  // ─────────────────────────────────────────────
  // Drawer methods
  // ─────────────────────────────────────────────

  void _showCalculatorDialog() {
    showCalculatorDialog(context);
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
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(hintText: 'اختر اسم العميل'),
                  items: _clients
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                      _balance =
                          doc.exists ? (doc['balance'] ?? 0.0).toDouble() : 0.0;
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
                                fontSize: 14.sp, fontWeight: FontWeight.bold)),
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
                    child:
                        Text('إغلاق', style: TextStyle(color: Colors.orange))),
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
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          content: Text('هل تريد مسح جميع المنتجات من القائمة الحالية؟',
              style: TextStyle(fontSize: 14.sp)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: Colors.orange)),
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
                    builder: (_) => InvoiceDetailPage(invoice: _lastInvoice!)));
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
                content: Text('ميزة استيراد عروض الأسعار ستكون متاحة قريبًا.',
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
        onTap: () {
          Navigator.pop(context);
          _addNewProductInline();
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

  static const double _invoiceSerialColWidth = 20;
  static const double _invoicePriceColWidth = 42;
  static const double _invoiceQtyColWidth = 30;
  static const double _invoiceTotalColWidth = 48;
  static const double _invoiceDragColWidth = 14;

  Widget _invoiceHeaderCell(
    String label, {
    int flex = 1,
    double? width,
    TextAlign align = TextAlign.center,
    bool compact = false,
    double? fontSize,
    bool expanded = true,
  }) {
    final cell = Container(
      margin: EdgeInsets.symmetric(
        horizontal: compact ? 1.w : 2.w,
        vertical: compact ? 1.h : 2.h,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 1.w : 4.w,
        vertical: compact ? 3.h : 8.h,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
      ),
      alignment:
          align == TextAlign.right ? Alignment.centerRight : Alignment.center,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: fontSize ?? (compact ? 11.sp : 12.sp),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (width != null) {
      return SizedBox(width: width.w, child: cell);
    }
    if (!expanded) {
      return cell;
    }
    return Expanded(flex: flex, child: cell);
  }

  Widget _invoiceValueCell({
    int flex = 1,
    double? width,
    required Widget child,
    Color? backgroundColor,
    Alignment alignment = Alignment.center,
    VoidCallback? onTap,
    bool compact = false,
    bool tight = false,
    bool expanded = true,
  }) {
    Widget box = Container(
      margin: EdgeInsets.symmetric(
        horizontal: tight ? 0.5.w : (compact ? 1.w : 2.w),
        vertical: tight ? 0.5.h : (compact ? 1.h : 2.h),
      ),
      padding: tight
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: width != null ? 1.w : (compact ? 2.w : 6.w),
              vertical: width != null ? 3.h : (compact ? 4.h : 10.h),
            ),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        border: Border.all(color: Colors.grey.shade400, width: 1),
        borderRadius: BorderRadius.circular(tight ? 4.r : 6.r),
      ),
      alignment: alignment,
      child: child,
    );
    if (onTap != null) {
      box = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: box,
      );
    }
    if (width != null) {
      return SizedBox(
        width: width.w,
        child: tight ? Center(child: box) : box,
      );
    }
    if (tight) {
      return Expanded(flex: flex, child: Center(child: box));
    }
    if (!expanded) {
      return box;
    }
    return Expanded(flex: flex, child: box);
  }

  // ─────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    double totalSum = _calculateTotalSum();
    double totalQty = _addedProducts.fold(
        0.0, (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0.0));

    return DesktopBackShortcuts(
      confirmBeforePop: () => HomePage.confirmNavigateBack(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          HomePage.confirmNavigateBack(context).then((shouldPop) {
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          });
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: const Color(0xffeeeced),
            drawer: _buildDrawer(),
            appBar: AppBar(
              backgroundColor: Colors.black.withOpacity(0.7),
              leading: AppBarNavLeading(
                openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                confirmBeforePop: () => HomePage.confirmNavigateBack(context),
              ),
              title: Text(_pageTitle,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold)),
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.white),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: Icon(Icons.menu, color: Colors.white, size: 24.sp),
                  tooltip: 'القائمة',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
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
                                      return _productsMatchingSearch(val.text);
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
                        if (!widget.isReturnInvoice) ...[
                          SizedBox(width: 4.w),
                          Material(
                            color: _retailOnlyMode
                                ? Colors.orange.withOpacity(0.9)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8.r),
                            child: InkWell(
                              onTap: _toggleRetailOnlyMode,
                              borderRadius: BorderRadius.circular(8.r),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10.w,
                                  vertical: 8.h,
                                ),
                                child: Text(
                                  _retailOnlyMode ? 'قطاعي ✓' : 'قطاعي',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.bold,
                                    color: _retailOnlyMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
                            onTap: () => setState(() {
                              _clientNameController.clear();
                              _clientBalance = 0.0;
                            }),
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
                          if (_clientBalance > 0)
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.red, size: 18.sp),
                          SizedBox(width: 4.w),
                          Expanded(
                            child: Text(_clientNameController.text,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Text(
                            'رصيد: ${invoiceAmount(_clientBalance)} ج.م',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: _clientBalance > 0
                                  ? Colors.red.shade700
                                  : Colors.black87,
                            ),
                          ),
                        ]),
                      ),

                    // ── Table headers (RTL: تعداد | المنتج | السعر | الكمية | الإجمالي) ──
                    Container(
                      color: Colors.grey.shade200,
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 6.h),
                      child: Row(
                        children: [
                          _invoiceHeaderCell(
                            'م',
                            width: _invoiceSerialColWidth,
                            compact: true,
                            fontSize: 9.sp,
                          ),
                          Expanded(
                            flex: 4,
                            child: _invoiceHeaderCell(
                              'المنتج',
                              flex: 1,
                              align: TextAlign.right,
                              expanded: false,
                            ),
                          ),
                          _invoiceHeaderCell(
                            'السعر',
                            width: _invoicePriceColWidth,
                            compact: true,
                          ),
                          _invoiceHeaderCell(
                            'الكمية',
                            width: _invoiceQtyColWidth,
                            compact: true,
                          ),
                          _invoiceHeaderCell(
                            'الإجمالي',
                            width: _invoiceTotalColWidth,
                            compact: true,
                          ),
                          SizedBox(width: _invoiceDragColWidth.w),
                        ],
                      ),
                    ),

                    // ── Products list ──
                    Expanded(
                      child: _addedProducts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_cart_outlined,
                                      size: 60.sp, color: Colors.grey.shade400),
                                  SizedBox(height: 8.h),
                                  Text('ابحث عن منتج وأضفه للفاتورة',
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : ReorderableListView.builder(
                              padding: EdgeInsets.only(top: 4.h, bottom: 80.h),
                              buildDefaultDragHandles: false,
                              itemCount: _addedProducts.length,
                              onReorder: _reorderAddedProducts,
                              itemBuilder: (context, index) {
                                final p = _addedProducts[index];
                                final amount =
                                    double.tryParse(p['amount'].toString()) ??
                                        0.0;
                                final total = (p['total'] as num).toDouble();
                                final price =
                                    (p['selectedPrice'] as num).toDouble();
                                final hasDiscount = (p['discount'] ?? 0.0) > 0;
                                return Material(
                                  key: ValueKey(p['lineId'] ?? index),
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6.w, vertical: 2.h),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => _showProductSheet(
                                                editIndex: index),
                                            onLongPress: () =>
                                                _confirmRemoveInvoiceLine(
                                                    index),
                                            child: Row(
                                              children: [
                                                _invoiceValueCell(
                                                  width: _invoiceSerialColWidth,
                                                  compact: true,
                                                  child: Text(
                                                    '${index + 1}',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 9.sp,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 4,
                                                  child: _invoiceValueCell(
                                                    flex: 1,
                                                    alignment:
                                                        Alignment.centerRight,
                                                    expanded: false,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          invoiceProductName(p),
                                                          textAlign:
                                                              TextAlign.right,
                                                          style: TextStyle(
                                                            fontSize: 10.sp,
                                                            height: 1.2,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          maxLines: 3,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        if (_getProductDescription(
                                                                p['product']
                                                                        ?.toString() ??
                                                                    '')
                                                            .isNotEmpty)
                                                          Text(
                                                            '💡 ${_getProductDescription(p['product']?.toString() ?? '')}',
                                                            textAlign:
                                                                TextAlign.right,
                                                            style: TextStyle(
                                                              fontSize: 8.5.sp,
                                                              color: Colors.blue
                                                                  .shade800,
                                                              fontStyle:
                                                                  FontStyle
                                                                      .italic,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                _invoiceValueCell(
                                                  width: _invoicePriceColWidth,
                                                  tight: true,
                                                  child: Text(
                                                    invoiceAmount(price),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 11.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                                _invoiceValueCell(
                                                  width: _invoiceQtyColWidth,
                                                  tight: true,
                                                  backgroundColor: Colors.teal
                                                      .withOpacity(0.08),
                                                  onTap: () =>
                                                      _incrementInvoiceLineQuantity(
                                                          index),
                                                  child: Text(
                                                    invoiceQty(amount),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 11.sp,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.teal.shade700,
                                                    ),
                                                  ),
                                                ),
                                                _invoiceValueCell(
                                                  width: _invoiceTotalColWidth,
                                                  tight: true,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        invoiceAmount(total),
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 11.sp,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: hasDiscount
                                                              ? Colors.orange
                                                                  .shade700
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                      if (hasDiscount)
                                                        Text(
                                                          '- ${p['discount']}${p['discountIsPercent'] == true ? '%' : ' ج.م'}',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 9.sp,
                                                            color: Colors.orange
                                                                .shade600,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () =>
                                                _showReorderInvoiceLineSheet(
                                                    index),
                                            child: SizedBox(
                                              width: _invoiceDragColWidth.w,
                                              height: 36.h,
                                              child: Icon(
                                                Icons.drag_handle,
                                                color: Colors.grey.shade600,
                                                size: 18.sp,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
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
                            invoiceAmount(totalSum),
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
                          Text(invoiceQty(totalQty),
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
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────

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

class _PriceTierBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PriceTierBtn({
    Key? key,
    required this.label,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.w,
        height: 32.w,
        decoration: BoxDecoration(
          color:
              selected ? Colors.orange.withOpacity(0.85) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({Key? key, required this.icon, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.w,
        height: 36.w,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18.sp),
      ),
    );
  }
}

class _SheetValueBox extends StatelessWidget {
  final String value;
  const _SheetValueBox({Key? key, required this.value}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}
