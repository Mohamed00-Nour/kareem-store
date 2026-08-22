import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screeens/AddProductPage.dart';
import '../Services/invoice_number_utils.dart';
import '../Services/invoice_stock_service.dart';
import '../Services/supplier_invoice_balance_sync_service.dart';
import '../Services/supplier_statement_pdf_service.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';
import 'SupplierBalanceHistoryPage.dart';

class SupplierInvoicesPage extends StatefulWidget {
  final String supplierId;

  const SupplierInvoicesPage({Key? key, required this.supplierId})
      : super(key: key);

  @override
  _SupplierInvoicesPageState createState() => _SupplierInvoicesPageState();
}

class _SupplierInvoicesPageState extends State<SupplierInvoicesPage> {
  static const int _pageSize = 20;

  String? _supplierName;
  double? _currentSupplierBalance;
  String _userRole = 'user';

  final TextEditingController _balanceController = TextEditingController();
  final TextEditingController _addBalanceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _isSaving = false;
  bool _generatingStatement = false;
  bool _isLoadingInvoices = true;
  bool _isLoadingMoreInvoices = false;
  bool _hasMoreInvoices = true;
  bool _showPayments = false; // toggle: show payment/voucher cards in the list

  List<QueryDocumentSnapshot> _invoices = [];
  List<QueryDocumentSnapshot> _returnInvoices = [];
  List<QueryDocumentSnapshot> _payments = [];
  DocumentSnapshot? _lastInvoiceDoc;

  final Set<String> _expandedInvoiceIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _fetchSupplierName();
    _fetchInvoices(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _balanceController.dispose();
    _addBalanceController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
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

  void _onScroll() {
    if (!_scrollController.hasClients || _searchQuery.isNotEmpty) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    _loadMoreInvoices();
  }

  Future<void> _fetchSupplierName() async {
    // 1. Read directly from local Hive (0ms)
    final local = SupplierRepository.instance.getById(widget.supplierId);
    if (local != null && mounted) {
      setState(() {
        _supplierName = local.name;
        _currentSupplierBalance = local.balance;
      });
    }

    // 2. Background refresh & history sync if online
    try {
      if (ConnectivityService.instance.isOnline) {
        await BalanceHistoryRepository.instance
            .fullSyncForSupplier(widget.supplierId);

        final doc = await FirebaseFirestore.instance
            .collection('suppliers')
            .doc(widget.supplierId)
            .get();
        if (mounted && doc.exists) {
          final data = doc.data();
          if (data != null) {
            final resolvedName =
                data['name'] ?? data['supplierName'] ?? 'المورد';
            final Map<String, dynamic> localData =
                Map<String, dynamic>.from(data);
            localData['name'] = resolvedName;
            localData['balance'] =
                (data['totalBalance'] ?? data['balance'] ?? 0.0).toDouble();

            await SupplierRepository.instance
                .upsertLocal(widget.supplierId, localData);

            final refreshed =
                SupplierRepository.instance.getById(widget.supplierId);
            if (mounted) {
              setState(() {
                _supplierName = refreshed?.name ?? resolvedName;
                _currentSupplierBalance = refreshed?.balance ??
                    (data['totalBalance'] ?? data['balance'] ?? 0.0).toDouble();
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  Query _invoicesQuery() => FirebaseFirestore.instance
      .collection('suppliers')
      .doc(widget.supplierId)
      .collection('buying invoices')
      .orderBy('date', descending: true);

  Query _returnInvoicesQuery() => FirebaseFirestore.instance
      .collection('suppliers')
      .doc(widget.supplierId)
      .collection('returnBuyingInvoices')
      .orderBy('date', descending: true);

  Query _paymentsQuery() => FirebaseFirestore.instance
      .collection('suppliers')
      .doc(widget.supplierId)
      .collection('balanceHistory')
      .orderBy('timestamp', descending: true);

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
      Query query = _invoicesQuery().limit(_pageSize);
      if (!reset && _lastInvoiceDoc != null) {
        query = query.startAfterDocument(_lastInvoiceDoc!);
      }

      final Future<QuerySnapshot> invoiceFuture = query.get();
      final Future<QuerySnapshot?> returnFuture = reset
          ? _returnInvoicesQuery().get()
          : Future<QuerySnapshot?>.value(null);
      final Future<QuerySnapshot?> paymentFuture =
          reset ? _paymentsQuery().get() : Future<QuerySnapshot?>.value(null);

      final snap = await invoiceFuture;
      final retSnap = await returnFuture;
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
          _payments = (paySnap?.docs ?? []).where((doc) {
            final t =
                (doc.data() as Map<String, dynamic>)['type']?.toString() ?? '';
            return t != 'buying' && t != 'return';
          }).toList();
        } else {
          _invoices.addAll(snap.docs);
        }
        if (snap.docs.isNotEmpty) {
          _lastInvoiceDoc = snap.docs.last;
        }
        _hasMoreInvoices = snap.docs.length >= _pageSize;
        _isLoadingInvoices = false;
        _isLoadingMoreInvoices = false;
      });
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
    _fetchSupplierName();
    await _fetchInvoices(reset: true);
  }

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

    if (notesText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال البيان')),
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

    try {
      // 1. Get current balance from local Hive immediately
      final supplierLocal =
          SupplierRepository.instance.getById(widget.supplierId);
      final double currentBalance =
          supplierLocal?.balance ?? _currentSupplierBalance ?? 0.0;
      final String supplierName =
          supplierLocal?.name ?? _supplierName ?? widget.supplierId;

      final double newBalance = isAddition
          ? currentBalance + enteredBalance
          : currentBalance - enteredBalance;

      final historyId = DateTime.now().millisecondsSinceEpoch.toString();

      // 2. Save to local Hive database immediately (<1ms)
      await SupplierRepository.instance
          .updateLocalBalance(widget.supplierId, newBalance);

      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: historyId,
          parentId: widget.supplierId,
          parentType: 'supplier',
          enteredBalance: enteredBalance,
          balanceBefore: currentBalance,
          type: isAddition ? 'addition' : 'voucher',
          notes: notesText,
          timestamp: DateTime.now(),
        ),
      );

      if (!isAddition) {
        await BoxRepository.instance.decrement(enteredBalance);
      }

      _balanceController.clear();
      _addBalanceController.clear();
      _notesController.clear();

      if (mounted) {
        setState(() {
          _currentSupplierBalance = newBalance;
        });
        _fetchSupplierName();
        _refreshInvoices();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الرصيد بنجاح')),
        );
      }

      // 3. Sync to Firestore asynchronously in background (non-blocking)
      _syncSupplierBalanceToFirestoreInBackground(
        supplierId: widget.supplierId,
        supplierName: supplierName,
        newBalance: newBalance,
        currentBalance: currentBalance,
        enteredBalance: enteredBalance,
        isAddition: isAddition,
        notesText: notesText,
        historyId: historyId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الرصيد: $e')),
        );
      }
    }
  }

  void _syncSupplierBalanceToFirestoreInBackground({
    required String supplierId,
    required String supplierName,
    required double newBalance,
    required double currentBalance,
    required double enteredBalance,
    required bool isAddition,
    required String notesText,
    required String historyId,
  }) async {
    try {
      final bool isOnline = ConnectivityService.instance.isOnline;
      if (isOnline) {
        final supplierRef =
            FirebaseFirestore.instance.collection('suppliers').doc(supplierId);

        await supplierRef
            .update({'totalBalance': newBalance, 'balance': newBalance});

        if (!isAddition) {
          final voucherSnap = await FirebaseFirestore.instance
              .collection('supplier_vouchers')
              .orderBy('voucherNumber', descending: true)
              .limit(1)
              .get();
          final nextVoucher = voucherSnap.docs.isNotEmpty
              ? (voucherSnap.docs.first['voucherNumber'] as int) + 1
              : 1;

          final voucherRef = await FirebaseFirestore.instance
              .collection('supplier_vouchers')
              .add({
            'supplierId': supplierId,
            'supplierName': supplierName,
            'direction': 'عليه',
            'amount': enteredBalance,
            'description':
                notesText.isNotEmpty ? notesText : 'سداد نقدي للمورد',
            'date': Timestamp.now(),
            'timestamp': DateTime.now(),
            'voucherNumber': nextVoucher,
          });

          await supplierRef.collection('balanceHistory').doc(historyId).set({
            'enteredBalance': enteredBalance,
            'balanceBefore': currentBalance,
            'type': 'voucher',
            'voucherId': voucherRef.id,
            'notes': notesText.isNotEmpty ? notesText : 'سداد نقدي للمورد',
            'timestamp': DateTime.now(),
          });

          DocumentReference boxDocRef =
              FirebaseFirestore.instance.collection('box').doc('mainBox');
          await boxDocRef.set(
            {'value': FieldValue.increment(-enteredBalance)},
            SetOptions(merge: true),
          );

          await boxDocRef.collection('changes').add({
            'date': FieldValue.serverTimestamp(),
            'value': enteredBalance,
            'type': 'decrement',
            'name': supplierName,
            'notes': notesText,
            'invoiceNumber': null,
          });
        } else {
          await supplierRef.collection('balanceHistory').doc(historyId).set({
            'enteredBalance': enteredBalance,
            'balanceBefore': currentBalance,
            'type': 'addition',
            'notes': notesText.isNotEmpty ? notesText : 'إضافة رصيد للمورد',
            'timestamp': DateTime.now(),
          });
        }
      }
    } catch (_) {}
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ليس لديك صلاحية'),
          content: const Text('ليس لديك الصلاحية لتنفيذ هذا الإجراء'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
  }

  void _handleEditInvoice(DocumentSnapshot invoice) {
    if (_userRole == 'admin') {
      final invoiceData = Map<String, dynamic>.from(invoice.data() as Map);
      invoiceData['id'] = invoiceData['invoiceId'] ?? invoice.id;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddProductPage(invoiceToEdit: invoiceData),
        ),
      ).then((saved) {
        if (saved == true) {
          _refreshInvoices();
        }
      });
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
              child: Text('إلغاء',
                  style: TextStyle(color: Colors.black.withOpacity(0.7))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmDelete != true) return;

    try {
      // 1. Get invoice data from local Hive or Firestore
      Map<String, dynamic>? invoiceData;
      final localInv = InvoiceRepository.instance.getBuyingById(invoiceId);
      if (localInv != null) {
        invoiceData = localInv.toMap();
      }

      if (invoiceData == null) {
        final invoiceDoc = await FirebaseFirestore.instance
            .collection('suppliers')
            .doc(widget.supplierId)
            .collection('buying invoices')
            .doc(invoiceId)
            .get();

        if (invoiceDoc.exists) {
          invoiceData = invoiceDoc.data();
        } else {
          final rootDoc = await FirebaseFirestore.instance
              .collection('buying invoices')
              .doc(invoiceId)
              .get();
          if (rootDoc.exists) {
            invoiceData = rootDoc.data();
          }
        }
      }

      final products =
          List<Map<String, dynamic>>.from(invoiceData?['products'] ?? []);
      final paidAmount = invoiceNum(invoiceData?['paidAmount']);
      final totalSum = invoiceNum(invoiceData?['totalSum']);
      final rootInvoiceId = invoiceData?['invoiceId']?.toString() ?? invoiceId;

      // 2. Decrement stock in local Hive (purchase invoice added stock, deleting it removes that stock)
      if (products.isNotEmpty) {
        await InvoiceStockService.applyStockChanges(
          lines: products,
          restore: false,
          changeDate: DateTime.now(),
          changeTypeWhenDecrease: 'decrease',
        );
      }

      // 3. Delete invoice locally from Hive
      await InvoiceRepository.instance.deleteBuyingLocal(invoiceId);
      if (rootInvoiceId.isNotEmpty && rootInvoiceId != invoiceId) {
        await InvoiceRepository.instance.deleteBuyingLocal(rootInvoiceId);
      }

      // 4. Delete balance history entries locally from Hive
      await BalanceHistoryRepository.instance
          .deleteByInvoiceId('supplier', widget.supplierId, invoiceId);
      if (rootInvoiceId.isNotEmpty && rootInvoiceId != invoiceId) {
        await BalanceHistoryRepository.instance
            .deleteByInvoiceId('supplier', widget.supplierId, rootInvoiceId);
      }

      // 5. Adjust Cash Box locally if there was a payment (paid cash is returned to box)
      if (paidAmount > 0) {
        await BoxRepository.instance.increment(paidAmount);
      }

      // 6. Update supplier balance locally in Hive
      final unpaid = totalSum - paidAmount;
      final localSup = SupplierRepository.instance.getById(widget.supplierId) ??
          SupplierRepository.instance.findByName(_supplierName ?? '');
      if (localSup != null) {
        await SupplierRepository.instance
            .updateLocalBalance(localSup.id, localSup.balance - unpaid);
      }

      // 7. Enqueue background deletion to SyncQueue
      await SyncQueueManager.instance.enqueue(
        operationType: 'deleteBuyingInvoice',
        payload: {
          'supplierId': widget.supplierId,
          'invoiceId': rootInvoiceId,
          'supplierSubDocId': invoiceId,
          'products': products,
          'totalSum': totalSum,
          'paidAmount': paidAmount,
        },
      );

      // 8. Trigger sync
      ConnectivityService.instance.forceSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الفاتورة وتحديث المخزون بنجاح')),
      );
      await _refreshInvoices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء حذف الفاتورة: $e')),
      );
    }
  }

  void _handleDeleteInvoice(String invoiceId, double totalCost) {
    if (_userRole == 'admin') {
      _deleteInvoice(invoiceId, totalCost);
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
    SupplierStatementType statementType = SupplierStatementType.financial;
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
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
                      RadioListTile<SupplierStatementType>(
                        dense: true,
                        title: const Text('كشف حساب مالي (الدفعات فقط)'),
                        value: SupplierStatementType.financial,
                        groupValue: statementType,
                        onChanged: (v) => setDialog(() => statementType = v!),
                      ),
                      RadioListTile<SupplierStatementType>(
                        dense: true,
                        title: const Text('كشف حساب الفواتير'),
                        value: SupplierStatementType.invoices,
                        groupValue: statementType,
                        onChanged: (v) => setDialog(() => statementType = v!),
                      ),
                      RadioListTile<SupplierStatementType>(
                        dense: true,
                        title: const Text('كشف حساب فواتير المرتجع'),
                        value: SupplierStatementType.returns,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
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
      final file = await SupplierStatementPdfService.generate(
        supplierId: widget.supplierId,
        type: statementType,
        from: from,
        to: to,
      );

      if (!mounted) return;
      String title;
      if (statementType == SupplierStatementType.financial) {
        title = 'كشف حساب مالي للمورد';
      } else if (statementType == SupplierStatementType.returns) {
        title = 'كشف حساب فواتير المرتجع للمورد';
      } else {
        title = 'كشف حساب فواتير الشراء';
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
              'تعديل رصيد المورد',
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
                      labelText: 'خصم من الرصيد (سداد للمورد)',
                      labelStyle: TextStyle(
                        color: Colors.black.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.green,
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
                      labelText: 'إضافة إلى الرصيد (علينا للمورد)',
                      labelStyle: TextStyle(
                        color: Colors.black.withOpacity(0.7),
                        fontSize: 14.sp,
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.orange,
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
                      labelText: 'البيان / ملاحظات العملية (مطلوب)',
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
                  final deductText = _balanceController.text.trim();
                  final addText = _addBalanceController.text.trim();
                  final notesText = _notesController.text.trim();

                  if (deductText.isEmpty && addText.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال المبلغ')),
                    );
                    return;
                  }

                  if (notesText.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال البيان')),
                    );
                    return;
                  }

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
      builder: (context) =>
          SupplierBalanceHistoryPage(supplierId: widget.supplierId),
    ));
  }

  static DateTime _entryDate(_SupplierInvoiceEntry e) {
    final d = e.data;
    if (e.kind == _SupplierEntryKind.payment) {
      final ts = d['timestamp'] ?? d['date'];
      if (ts is Timestamp) return ts.toDate();
      if (ts is DateTime) return ts;
      return DateTime.now();
    }
    final ts = d['date'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return DateTime(0);
  }

  List<_SupplierInvoiceEntry> get _allMergedInvoices {
    final List<_SupplierInvoiceEntry> merged = [
      ..._invoices.map((d) =>
          _SupplierInvoiceEntry(doc: d, kind: _SupplierEntryKind.invoice)),
      ..._returnInvoices.map((d) => _SupplierInvoiceEntry(
          doc: d, kind: _SupplierEntryKind.returnInvoice)),
      ..._payments.map((d) =>
          _SupplierInvoiceEntry(doc: d, kind: _SupplierEntryKind.payment)),
    ];

    // Sort ascending by date to compute chronological running balances
    merged.sort((a, b) => _entryDate(a).compareTo(_entryDate(b)));

    var running = 0.0;
    for (final entry in merged) {
      final data = entry.data;
      data['_computedPrevBalance'] = running;

      if (entry.kind == _SupplierEntryKind.invoice) {
        final total = invoiceNum(data['totalSum']);
        final paid = invoiceNum(data['paidAmount']);
        running += (total - paid);
      } else if (entry.kind == _SupplierEntryKind.returnInvoice) {
        final total = invoiceNum(data['totalSum']);
        final paid = invoiceNum(data['paidAmount']);
        running -= (total - paid);
      } else if (entry.kind == _SupplierEntryKind.payment) {
        final type = data['type']?.toString() ?? '';
        if (type == 'buying_payment' || type == 'return_payment') continue;

        final entered = invoiceNum(
            data['enteredBalance'] ?? data['amount'] ?? data['value']);
        if (type == 'opening' || type == 'addition' || type == 'buying') {
          running += entered;
        } else if (type == 'deduction' || type == 'return') {
          running -= entered;
        }
      }
      data['_computedRemainingOwed'] = running;
    }

    // Sort descending (newest first) for UI display
    merged.sort((a, b) => _entryDate(b).compareTo(_entryDate(a)));
    return merged;
  }

  List<_SupplierInvoiceEntry> get _filteredInvoices {
    final all = _allMergedInvoices;
    final visible = _showPayments
        ? all
        : all.where((e) => e.kind != _SupplierEntryKind.payment).toList();
    if (_searchQuery.isEmpty) return visible;
    final q = _searchQuery.toLowerCase();
    return visible.where((entry) {
      final data = entry.data;
      if (entry.kind == _SupplierEntryKind.payment) {
        final notes = (data['notes'] ?? data['description'] ?? '')
            .toString()
            .toLowerCase();
        final amount =
            (data['enteredBalance'] ?? data['amount'] ?? 0).toString();
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

  Widget _buildPaymentCard(_SupplierInvoiceEntry entry) {
    final data = entry.data;
    final type = data['type']?.toString() ?? 'voucher';
    final amount = (data['enteredBalance'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble() ??
        0.0;
    final notes =
        (data['notes'] ?? data['description'] ?? '').toString().trim();
    final ts = data['timestamp'] ?? data['date'];
    final date =
        ts is Timestamp ? ts.toDate().toLocal() : (ts is DateTime ? ts : null);
    final formattedDate =
        date != null ? intl.DateFormat('yyyy-MM-dd').format(date) : '';
    final formattedTime =
        date != null ? intl.DateFormat('hh:mm a').format(date) : '';
    final voucherNumber = data['voucherNumber']?.toString() ?? '';

    String label;
    IconData icon;
    Color badgeColor;
    Color cardColor;
    Color amountColor;
    String sign;

    switch (type) {
      case 'buying_payment':
        label = 'سداد فاتورة شراء';
        icon = Icons.payments_outlined;
        badgeColor = Colors.green.shade700;
        cardColor = Colors.green.shade50;
        amountColor = Colors.green.shade800;
        sign = '-';
        break;
      case 'voucher':
      case 'deduction':
        label = 'سداد نقدي للمورد';
        icon = Icons.payments_outlined;
        badgeColor = Colors.green.shade700;
        cardColor = Colors.green.shade50;
        amountColor = Colors.green.shade800;
        sign = '-';
        break;
      case 'return_payment':
        label = 'تحصيل مرتجع';
        icon = Icons.undo_outlined;
        badgeColor = Colors.teal.shade700;
        cardColor = Colors.teal.shade50;
        amountColor = Colors.teal.shade800;
        sign = '+';
        break;
      case 'addition':
        label = 'إضافة رصيد للمورد';
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
      default:
        label = 'سداد / حركة رصيد';
        icon = Icons.payments_outlined;
        badgeColor = Colors.green.shade700;
        cardColor = Colors.green.shade50;
        amountColor = Colors.green.shade800;
        sign = '-';
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
                      if (voucherNumber.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'إيصال #$voucherNumber',
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.5),
      },
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            cell('المنتج', bold: true),
            cell('الكمية', bold: true),
            cell('السعر', bold: true),
            cell('الإجمالي', bold: true),
          ],
        ),
        for (final p in rows)
          TableRow(
            children: [
              cell((p['product'] ?? '').toString(), align: TextAlign.right),
              cell(invoiceQty(p['amount'])),
              cell(invoiceAmount(
                  p['buyingPrice'] ?? p['selectedPrice'] ?? p['price'])),
              cell(invoiceAmount(p['total'] ?? p['totalCost'])),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            cell('الإجمالي', bold: true, align: TextAlign.right),
            cell(invoiceQty(qtySum), bold: true),
            cell(''),
            cell(''),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(_SupplierInvoiceEntry entry) {
    if (entry.kind == _SupplierEntryKind.payment)
      return _buildPaymentCard(entry);

    final invoice = entry.doc;
    final bool isReturn = entry.kind == _SupplierEntryKind.returnInvoice;
    final invoiceData = Map<String, dynamic>.from(invoice.data() as Map);
    final dateField = invoiceData['date'];
    if (dateField is! Timestamp) {
      return const SizedBox.shrink();
    }

    final invoiceDate = dateField.toDate().toLocal();
    final formattedDate = invoiceDate.toString().split(' ')[0];
    final formattedTime = intl.DateFormat('hh:mm a').format(invoiceDate);

    final previousBalance = invoiceDynamicPreviousBalance(invoiceData);
    final remainingOwed = invoiceSupplierRemainingOwed(invoiceData);
    final totalSum = invoiceNum(invoiceData['totalSum']);
    final discount = invoiceResolveDiscount(invoiceData);

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
                                    'رقم الفاتورة: #${invoiceData['invoiceNumber'] ?? invoiceData['invoiceId'] ?? ''} (${invoiceAmount(totalSum)} ج.م)',
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
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _handleEditInvoice(invoice),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _handleDeleteInvoice(
                        invoice.id,
                        totalSum,
                      ),
                    ),
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
                          'المدفوع: ${invoiceAmount(invoiceData['paidAmount'])}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'المتبقي من الفاتورة: ${invoiceAmount(totalSum - invoiceNum(invoiceData['paidAmount']))}',
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
            title: Text(
              _supplierName != null ? 'فواتير $_supplierName' : 'فواتير المورد',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              // Toggle: show / hide payment cards
              IconButton(
                tooltip: _showPayments ? 'إخفاء الدفعات' : 'عرض الدفعات',
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    _showPayments ? Icons.payments : Icons.payments_outlined,
                    key: ValueKey(_showPayments),
                    color: _showPayments
                        ? Colors.greenAccent.shade200
                        : Colors.white,
                  ),
                ),
                onPressed: _isSaving
                    ? null
                    : () => setState(() => _showPayments = !_showPayments),
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                tooltip: 'تاريخ الرصيد',
                onPressed: _isSaving ? null : _navigateToBalanceHistory,
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
                  textDirection: ui.TextDirection.rtl,
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
                                setState(() => _searchQuery = '');
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
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
              ),
              // ── Supplier Name & Running Balance Header Card (Under Search Bar) ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade800, Colors.orange.shade600],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Directionality(
                    textDirection: ui.TextDirection.rtl,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.person,
                                  color: Colors.white, size: 22.sp),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  _supplierName ?? 'المورد',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'الرصيد: ',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              Text(
                                '${(_currentSupplierBalance ?? 0.0).toStringAsFixed(2)} ج.م',
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                              controller: _scrollController,
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
                                return _buildInvoiceCard(
                                    _filteredInvoices[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
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

enum _SupplierEntryKind { invoice, returnInvoice, payment }

class _SupplierInvoiceEntry {
  final QueryDocumentSnapshot doc;
  final _SupplierEntryKind kind;

  _SupplierInvoiceEntry({required this.doc, required this.kind});

  String get id => doc.id;
  Map<String, dynamic> get data => doc.data() as Map<String, dynamic>;
}
