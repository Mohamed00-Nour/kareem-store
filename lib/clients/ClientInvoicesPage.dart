library client_invoices_page;

import 'dart:async';
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
import '../Services/client_invoice_running_balance_service.dart';
import '../Services/client_statement_pdf_service.dart';
import '../Services/invoice_number_utils.dart';
import '../Services/invoice_stock_service.dart';
import '../Services/sales_invoice_actions_service.dart';
import '../Services/invoice_print_ui.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import '../repositories/product_repository.dart';
import '../sync/connectivity_service.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../Services/customer_operation_service.dart';
import '../Services/customer_balance_store.dart';
import '../Widgets/invoice_display_widgets.dart';
import '../local_db/hive_init.dart';

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
  final List<StreamSubscription> _localSubscriptions = [];
  bool _isSaving = false; // Add loading state
  bool _generatingStatement = false;
  bool _autoEditTriggered = false;
  List<_ProdInfo> _allProds = [];

  List<_ItemDoc> _invoices = [];
  List<_ItemDoc> _returnInvoices = [];
  List<_ItemDoc> _payments = [];
  bool _isLoadingInvoices = true;
  bool _showPayments = false; // toggle: show payment cards in the list
  final Set<String> _expandedInvoiceIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Loads all products from the **local Hive cache** — zero Firestore reads.
  /// Falls back to a direct Firestore fetch if the cache is empty (first launch
  /// before [DataSyncService.syncOnStartup()] completes).
  Future<void> _fetchAllProds() async {
    try {
      final cached = ProductRepository.instance.getAll();
      if (cached.isNotEmpty) {
        // Serve from local cache instantly (< 1ms).
        if (mounted) {
          setState(() {
            _allProds = cached
                .map((p) => _ProdInfo(
                      name: p.name,
                      sellingPrice1: p.sellingPrice1,
                      sellingPrice2: p.sellingPrice2,
                      sellingPrice3: p.sellingPrice3,
                      quantity: p.quantity,
                    ))
                .toList();
          });
        }
        return;
      }
    } catch (_) {}
  }

  double _numField(dynamic value) {
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is num) return value.toDouble();
    return 0.0;
  }

  Future<double> _productCostTotal(List<Map<String, dynamic>> products) async {
    return InvoiceStockService.computeCostTotalAsync(products);
  }

  Future<void> _fetchInvoices({bool reset = false}) async {
    _fetchClientName();
    if (reset && mounted) {
      setState(() {
        _isLoadingInvoices = true;
        _invoices = [];
        _returnInvoices = [];
        _payments = [];
      });
    }

    try {
      // 1. Read from local Hive immediately (0ms wait)
      final localSales = InvoiceRepository.instance.getSalesByClient(
        widget.clientId,
        clientName: _clientName,
      );
      final localReturns = InvoiceRepository.instance.getReturnsByClient(
        widget.clientId,
        clientName: _clientName,
      );
      final localPayments = BalanceHistoryRepository.instance.getForClient(
        widget.clientId,
      );

      final salesDocs = localSales
          .map((inv) => _ItemDoc(id: inv.id, data: inv.toMap()))
          .toList();
      final returnDocs = localReturns
          .map((inv) => _ItemDoc(id: inv.id, data: inv.toMap()))
          .toList();
      final paymentDocs = localPayments
          .where((bh) => bh.type != 'sale' && bh.type != 'return')
          .map((bh) => _ItemDoc(id: bh.id, data: bh.toMap()))
          .toList();

      if (mounted) {
        setState(() {
          _invoices = salesDocs;
          _returnInvoices = returnDocs;
          _payments = paymentDocs;
          _isLoadingInvoices = false;
        });
      }

      if (reset) {
        await _tryAutoEditInvoice();
      }

      // 2. Background sync from Firestore if online (fire-and-forget)
      if (reset && ConnectivityService.instance.isOnline) {
        _backgroundSyncInvoices();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingInvoices = false;
        });
      }
    }
  }

  Future<void> _backgroundSyncInvoices() async {
    try {
      // Hydrate guarded caches without assigning or repairing financial balances.
      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);
      await ClientRepository.instance.deltaSync();
      await BalanceHistoryRepository.instance
          .fullSyncForClient(widget.clientId);
      await InvoiceRepository.instance.deltaSyncSales();
      await InvoiceRepository.instance.deltaSyncReturns();

      await _fetchClientName();

      final localSales = InvoiceRepository.instance.getSalesByClient(
        widget.clientId,
        clientName: _clientName,
      );
      final localReturns = InvoiceRepository.instance.getReturnsByClient(
        widget.clientId,
        clientName: _clientName,
      );
      final localPayments = BalanceHistoryRepository.instance.getForClient(
        widget.clientId,
      );

      if (mounted) {
        final localClient =
            ClientRepository.instance.getById(widget.clientId) ??
                ClientRepository.instance.findByName(
                  _clientName ?? widget.clientId,
                );
        final ledgerBalance = localClient != null
            ? BalanceHistoryRepository.instance.calculateClientBalance(
                localClient.id,
                fallback: localClient.balance,
              )
            : _currentClientBalance ?? 0.0;
        setState(() {
          _currentClientBalance = ledgerBalance;
          _invoices = localSales
              .map((inv) => _ItemDoc(id: inv.id, data: inv.toMap()))
              .toList();
          _returnInvoices = localReturns
              .map((inv) => _ItemDoc(id: inv.id, data: inv.toMap()))
              .toList();
          _payments = localPayments
              .where((bh) => bh.type != 'sale' && bh.type != 'return')
              .map((bh) => _ItemDoc(id: bh.id, data: bh.toMap()))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshInvoices() async {
    _fetchClientName();
    await _fetchInvoices(reset: true);
  }

  Future<void> _tryAutoEditInvoice() async {
    if (_autoEditTriggered || widget.autoEditRootInvoiceId == null) return;

    for (final doc in _invoices) {
      if (doc.data['invoiceId']?.toString() == widget.autoEditRootInvoiceId ||
          doc.id == widget.autoEditRootInvoiceId) {
        _autoEditTriggered = true;
        _handleEditInvoice(doc.id, doc.data);
        return;
      }
    }
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

    if (notesText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال البيان')),
      );
      return;
    }

    final isAddition = addText.isNotEmpty;
    final valueText = isAddition ? addText : deductText;
    double enteredBalance = invoiceTryParseAmount(valueText) ?? 0.0;

    if (enteredBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
      );
      return;
    }

    try {
      await CustomerOperationService.savePayment(
          clientId: widget.clientId,
          amount: enteredBalance,
          isAddition: isAddition,
          notes: notesText);
      ConnectivityService.instance.forceSync();
      _balanceController.clear();
      _addBalanceController.clear();
      _notesController.clear();
      await _refreshInvoices();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحفظ محلياً')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الرصيد: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _invoicePayloadForEdit(
      String invoiceId, Map<String, dynamic> invoiceData) async {
    return SalesInvoiceActionsService.buildEditPayload(
      invoiceData,
      clientSubDocId: invoiceId,
    );
  }

  Future<void> _showEditInvoiceDialog(
      String invoiceId, Map<String, dynamic> invoiceData) async {
    final payload = await _invoicePayloadForEdit(invoiceId, invoiceData);

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

  Future<void> _deleteInvoice(
    String invoiceId,
    double totalCost, {
    Map<String, dynamic>? invoiceData,
  }) async {
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text(
              'هل أنت متأكد أنك تريد حذف هذه الفاتورة؟\nسيتم إرجاع المنتجات إلى المخزون وإعادة حساب رصيد العميل.'),
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

    if (confirmDelete != true || !mounted) {
      return;
    }

    try {
      final rootId = invoiceData == null
          ? invoiceId
          : SalesInvoiceActionsService.rootInvoiceIdFrom(invoiceData);
      await CustomerOperationService.deleteInvoice(
          rootId.isEmpty ? invoiceId : rootId,
          clientSubDocId: invoiceId);
      ConnectivityService.instance.forceSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تم حذف الفاتورة وإرجاع المنتجات للمخزون وإعادة حساب الرصيد'),
          ),
        );
        _fetchClientName();
        await _refreshInvoices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الفاتورة: $e')),
        );
      }
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

  void _handleDeleteInvoice(
    String invoiceId,
    double totalCost, {
    Map<String, dynamic>? invoiceData,
  }) {
    if (_userRole == 'admin') {
      _deleteInvoice(invoiceId, totalCost, invoiceData: invoiceData);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _handleEditInvoice(String invoiceId, Map<String, dynamic> invoiceData) {
    if (_userRole == 'admin') {
      _showEditInvoiceDialog(invoiceId, invoiceData);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  // ── Return-invoice edit / delete ─────────────────────────────────

  Future<void> _showEditReturnInvoiceDialog(
      String invoiceId, Map<String, dynamic> invoiceData) async {
    final payload = await _invoicePayloadForEdit(invoiceId, invoiceData);
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

  Future<void> _deleteReturnInvoice(
      String docId, Map<String, dynamic> data) async {
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
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final rootId = SalesInvoiceActionsService.rootInvoiceIdFrom(data);
      await CustomerOperationService.deleteInvoice(
          rootId.isEmpty ? docId : rootId,
          isReturn: true,
          clientSubDocId: docId);
      ConnectivityService.instance.forceSync();
      await _refreshInvoices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف المرتجع: $e')),
        );
      }
    }
  }

  void _handleEditReturnInvoice(
      String invoiceId, Map<String, dynamic> invoiceData) {
    if (_userRole == 'admin') {
      _showEditReturnInvoiceDialog(invoiceId, invoiceData);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _handleDeleteReturnInvoice(
      String invoiceId, Map<String, dynamic> invoiceData) {
    if (_userRole == 'admin') {
      _deleteReturnInvoice(invoiceId, invoiceData);
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
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12)),
              children: [
                cell(invoiceProductName(p), align: TextAlign.right),
                cell(invoiceQty(p['amount'])),
                cell(invoiceAmount(invoiceLineUnitPrice(p))),
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
                cell(invoiceAmount(invoiceLineUnitPrice(p))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
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
    final notes =
        (data['notes'] ?? data['description'] ?? '').toString().trim();
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
    for (final box in [
      clientsBox,
      invoicesBox,
      returnInvoicesBox,
      balanceHistoryBox
    ]) {
      _localSubscriptions.add(box.watch().listen((_) => _fetchInvoices()));
    }

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
    _fetchInvoices(reset: true);
  }

  Future<void> _fetchClientName() async {
    // 1. Read directly from local Hive (0ms)
    final local = ClientRepository.instance.getById(widget.clientId) ??
        ClientRepository.instance.findByName(widget.clientId);
    if (local != null && mounted) {
      final ledgerBalance = BalanceHistoryRepository.instance
          .calculateClientBalance(local.id, fallback: local.balance);
      setState(() {
        _clientName = local.name;
        _currentClientBalance = ledgerBalance;
      });
    }
  }

  @override
  void dispose() {
    for (final sub in _localSubscriptions) {
      sub.cancel();
    }
    _searchController.dispose();
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

  /// Combines sales invoices, return invoices, and payment entries sorted newest first,
  /// with dynamically calculated chronological running balances.
  List<_InvoiceEntry> get _allMergedInvoices {
    final sales =
        _invoices.map((doc) => Map<String, dynamic>.from(doc.data)).toList();
    final returns = _returnInvoices
        .map((doc) => Map<String, dynamic>.from(doc.data))
        .toList();
    final payments =
        _payments.map((doc) => Map<String, dynamic>.from(doc.data)).toList();

    ClientInvoiceRunningBalanceService.apply(
      salesInvoices: sales,
      returnInvoices: returns,
      payments: payments,
      initialBalance: CustomerBalanceStore.hasBase(widget.clientId)
          ? ClientInvoiceRunningBalanceService.carryForward(
              currentBalance: ClientRepository.instance
                  .computeLiveBalanceFromHive(widget.clientId),
              salesInvoices: sales,
              returnInvoices: returns,
              payments: payments)
          : 0,
    );

    final List<_InvoiceEntry> merged = [
      for (var i = 0; i < _invoices.length; i++)
        _InvoiceEntry(
          id: _invoices[i].id,
          data: sales[i],
          kind: _EntryKind.invoice,
        ),
      for (var i = 0; i < _returnInvoices.length; i++)
        _InvoiceEntry(
          id: _returnInvoices[i].id,
          data: returns[i],
          kind: _EntryKind.returnInvoice,
        ),
      for (var i = 0; i < _payments.length; i++)
        _InvoiceEntry(
          id: _payments[i].id,
          data: payments[i],
          kind: _EntryKind.payment,
        ),
    ];

    // Sort descending (newest first) for UI display
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
        final notes = (data['notes'] ?? data['description'] ?? '')
            .toString()
            .toLowerCase();
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

    final bool isReturn = entry.kind == _EntryKind.returnInvoice;
    final invoiceData = Map<String, dynamic>.from(entry.data);
    final dateField = invoiceData['date'];

    DateTime invoiceDate;
    if (dateField is Timestamp) {
      invoiceDate = dateField.toDate().toLocal();
    } else if (dateField is DateTime) {
      invoiceDate = dateField.toLocal();
    } else if (dateField is String) {
      invoiceDate = DateTime.tryParse(dateField)?.toLocal() ?? DateTime.now();
    } else {
      invoiceDate = DateTime.now();
    }

    final formattedDate = invoiceDate.toString().split(' ')[0];
    final formattedTime = intl.DateFormat('hh:mm a').format(invoiceDate);

    final String notes =
        (invoiceData['notes'] ?? invoiceData['description'] ?? '')
            .toString()
            .trim();

    final totalSum = invoiceNum(invoiceData['totalSum']);
    final invoiceId = entry.id;
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
                                    'رقم الفاتورة: #${invoiceData['invoiceNumber']} (${invoiceAmount(totalSum)} ج.م)',
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
                        onPressed: () =>
                            _handleEditInvoice(invoiceId, invoiceData),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _handleDeleteInvoice(
                          invoiceId,
                          totalSum,
                          invoiceData: invoiceData,
                        ),
                      ),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.edit,
                            color: Colors.deepOrangeAccent),
                        tooltip: 'تعديل المرتجع',
                        onPressed: () =>
                            _handleEditReturnInvoice(invoiceId, invoiceData),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_forever, color: Colors.red),
                        tooltip: 'حذف المرتجع',
                        onPressed: () =>
                            _handleDeleteReturnInvoice(invoiceId, invoiceData),
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
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6.r),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.note_alt_outlined,
                          size: 16.sp, color: Colors.orange.shade800),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          'بيانات إضافية: $notes',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 10.h),
              _buildInvoiceProductsTable(
                List<dynamic>.from(invoiceData['products'] ?? []),
              ),
              InvoiceTotalsFooter(invoice: invoiceData),
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
                    _showPayments ? Icons.payments : Icons.payments_outlined,
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
              // ── Client Name & Balance Header Card ──
              Builder(
                builder: (context) {
                  final String name = _clientName ?? 'جاري التحميل...';
                  final double balance = _currentClientBalance ?? 0.0;

                  return Container(
                    margin: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 4.h),
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade800,
                          Colors.orange.shade600
                        ],
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
                      textDirection: TextDirection.rtl,
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
                                    name,
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
                                  '${balance.toStringAsFixed(2)} ج.م',
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
                  );
                },
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 6.h),
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
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                return _buildInvoiceCard(
                                    _filteredInvoices[index]);
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
  List<_ItemDoc> _historyDocs = [];
  bool _isLoading = true;
  StreamSubscription? _historySubscription;
  final List<StreamSubscription> _financialSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadFromLocalCache();
    _listenToHistory();
    for (final box in [clientsBox, invoicesBox, returnInvoicesBox]) {
      _financialSubscriptions
          .add(box.watch().listen((_) => _loadFromLocalCache()));
    }
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    for (final sub in _financialSubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _loadFromLocalCache() {
    final locals =
        BalanceHistoryRepository.instance.getForClient(widget.clientId);
    final docs =
        locals.map((bh) => _ItemDoc(id: bh.id, data: bh.toMap())).toList();

    // 1. Sort ascending (oldest first)
    final sortedAscending = _sortDocsAscending(docs);

    // 2. Compute dynamic chronological running balances
    final cachedNet = sortedAscending.fold<double>(
        0,
        (sum, item) =>
            sum +
            (_isIncreaseType(item.data['type']?.toString() ?? '') ? 1 : -1) *
                invoiceNum(item.data['enteredBalance']));
    double running = CustomerBalanceStore.hasBase(widget.clientId)
        ? ClientRepository.instance
                .computeLiveBalanceFromHive(widget.clientId) -
            cachedNet
        : 0;
    for (final item in sortedAscending) {
      final data = item.data;
      final type = data['type']?.toString() ?? 'deduction';
      final entered = (data['enteredBalance'] as num?)?.toDouble() ?? 0.0;
      final isIncrease = _isIncreaseType(type);

      item.computedBefore = running;
      if (isIncrease) {
        running += entered;
      } else {
        running -= entered;
      }
      item.computedAfter = running;
    }

    // 3. Display uses the computed running balance but does NOT write it
    //    back to Hive — that would create a side-effect from a display-only page.
    //    Balance persistence is handled exclusively by write operations (save invoice,
    //    save payment, syncForClient, etc.).

    // 4. Display newest first using the same order that produced the balances.
    final sortedDescending = sortedAscending.reversed.toList();

    if (mounted) {
      setState(() {
        _historyDocs = sortedDescending;
        _isLoading = false;
      });
    }
  }

  void _listenToHistory() {
    _historySubscription?.cancel();
    _historySubscription =
        balanceHistoryBox.watch().listen((_) => _loadFromLocalCache());
    if (ConnectivityService.instance.isOnline) {
      BalanceHistoryRepository.instance
          .fullSyncForClient(widget.clientId)
          .catchError((Object e) {
        appMetaBox.put('cloudRefreshError', e.toString());
      });
    }
  }

  static int _typePriorityAscending(String type) {
    switch (type) {
      case 'opening':
        return 0;
      case 'sale':
        return 1;
      case 'sale_payment':
        return 2;
      case 'return':
        return 3;
      case 'return_payment':
        return 4;
      case 'addition':
        return 5;
      case 'deduction':
        return 6;
      default:
        return 7;
    }
  }

  static List<_ItemDoc> _sortDocsAscending(List<_ItemDoc> docs) {
    final sorted = List<_ItemDoc>.from(docs);
    sorted.sort((a, b) {
      final dataA = a.data;
      final dataB = b.data;
      final typeA = dataA['type']?.toString() ?? '';
      final typeB = dataB['type']?.toString() ?? '';

      if (typeA == 'opening' && typeB != 'opening') return -1;
      if (typeB == 'opening' && typeA != 'opening') return 1;

      final dateA = _parseDocDate(dataA['timestamp'] ?? dataA['date']);
      final dateB = _parseDocDate(dataB['timestamp'] ?? dataB['date']);

      if (dateA != null && dateB != null) {
        final dayCmp = _dateOnly(dateA).compareTo(_dateOnly(dateB));
        if (dayCmp != 0) return dayCmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      final invA = _docInvoiceNumber(dataA);
      final invB = _docInvoiceNumber(dataB);
      if (invA > 0 && invB > 0 && invA != invB) {
        return invA.compareTo(invB);
      }

      if (dateA != null && dateB != null) {
        final timeCmp = dateA.compareTo(dateB);
        if (timeCmp != 0) return timeCmp;
      }

      final priorityCmp = _typePriorityAscending(typeA)
          .compareTo(_typePriorityAscending(typeB));
      if (priorityCmp != 0) return priorityCmp;

      return a.id.compareTo(b.id);
    });
    return sorted;
  }

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

  static DateTime? _parseDocDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _docInvoiceNumber(Map<String, dynamic> data) =>
      int.tryParse(data['invoiceNumber']?.toString().trim() ?? '') ?? 0;

  static List<_ItemDoc> _sortDocs(List<_ItemDoc> docs) {
    final sorted = List<_ItemDoc>.from(docs);
    sorted.sort((a, b) {
      final dataA = a.data;
      final dataB = b.data;
      final typeA = dataA['type']?.toString() ?? '';
      final typeB = dataB['type']?.toString() ?? '';

      // Compare by date and time descending (newest first at the top)
      final dateA = _parseDocDate(dataA['timestamp'] ?? dataA['date']);
      final dateB = _parseDocDate(dataB['timestamp'] ?? dataB['date']);

      if (dateA != null && dateB != null) {
        final cmp = dateB.compareTo(dateA);
        if (cmp != 0) return cmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      // If dates are identical, opening goes last (oldest) in a descending view
      if (typeA == 'opening' && typeB != 'opening') return 1;
      if (typeB == 'opening' && typeA != 'opening') return -1;

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

  Future<void> _editEntry(_InvoiceEntry entry) async {
    final data = entry.data;
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
      if (['sale', 'return', 'sale_payment', 'return_payment'].contains(type)) {
        final isReturn = type.startsWith('return');
        final invoice = isReturn
            ? InvoiceRepository.instance.getReturnById(invoiceId)
            : InvoiceRepository.instance.getSaleById(invoiceId);
        if (invoice == null)
          throw StateError('Invoice must be cached before editing its history');
        final data = invoice.toMap();
        data[type.endsWith('payment') ? 'paidAmount' : 'totalSum'] = newAmount;
        await CustomerOperationService.saveInvoice(data,
            editing: true, isReturn: isReturn);
      } else {
        await CustomerOperationService.savePayment(
            clientId: widget.clientId,
            amount: newAmount,
            isAddition: type != 'deduction',
            notes: newNotes,
            historyId: entry.id);
      }
      ConnectivityService.instance.forceSync();
      _loadFromLocalCache();
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

  Future<void> _deleteEntry(_InvoiceEntry entry) async {
    final data = entry.data;
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
      if (type == 'sale' || type == 'return') {
        await CustomerOperationService.deleteInvoice(invoiceId,
            isReturn: type == 'return');
      } else if (type == 'sale_payment' || type == 'return_payment') {
        final isReturn = type == 'return_payment';
        final invoice = isReturn
            ? InvoiceRepository.instance.getReturnById(invoiceId)
            : InvoiceRepository.instance.getSaleById(invoiceId);
        if (invoice == null)
          throw StateError(
              'Invoice must be cached before deleting its payment');
        await CustomerOperationService.saveInvoice(
            {...invoice.toMap(), 'paidAmount': 0.0},
            editing: true, isReturn: isReturn);
      } else {
        await CustomerOperationService.savePayment(
            clientId: widget.clientId,
            amount: enteredBalance,
            isAddition: type != 'deduction',
            notes: '',
            historyId: entry.id,
            deleting: true);
      }
      ConnectivityService.instance.forceSync();
      _loadFromLocalCache();
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
            title: const Text('تاريخ الحركات'),
            backgroundColor: Colors.black.withOpacity(0.7),
            foregroundColor: Colors.white,
          ),
          body: _isLoading
              ? Center(
                  child:
                      CircularProgressIndicator(color: Colors.orange.shade700))
              : _historyDocs.isEmpty
                  ? const Center(
                      child:
                          Text('لا يوجد سجلات', style: TextStyle(fontSize: 16)))
                  : Directionality(
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
                                      label: Text('الحركة',
                                          textAlign: TextAlign.right),
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
                                      label: Text('التاريخ',
                                          textAlign: TextAlign.right),
                                    ),
                                    DataColumn(
                                      label: Text('إجراءات',
                                          textAlign: TextAlign.right),
                                    ),
                                  ],
                                  rows: _historyDocs.map((doc) {
                                    final data = doc.data;
                                    final type =
                                        data['type']?.toString() ?? 'deduction';
                                    final entered =
                                        (data['enteredBalance'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                    final isIncrease = _isIncreaseType(type);
                                    final before = doc.computedBefore ??
                                        (data['balanceBefore'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                    final after = doc.computedAfter ??
                                        (isIncrease
                                            ? before + entered
                                            : before - entered);
                                    final sign = isIncrease ? '+' : '-';
                                    final color =
                                        _colorForType(type, isIncrease);
                                    final description =
                                        _descriptionForEntry(data);

                                    final rawTs =
                                        data['timestamp'] ?? data['date'];
                                    DateTime timestamp = DateTime.now();
                                    if (rawTs is Timestamp) {
                                      timestamp = rawTs.toDate();
                                    } else if (rawTs is DateTime) {
                                      timestamp = rawTs;
                                    } else if (rawTs is String) {
                                      timestamp = DateTime.tryParse(rawTs) ??
                                          DateTime.now();
                                    } else if (rawTs is int) {
                                      timestamp =
                                          DateTime.fromMillisecondsSinceEpoch(
                                              rawTs);
                                    }
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
                                                constraints:
                                                    const BoxConstraints(),
                                                tooltip: 'تعديل',
                                                onPressed: _isBusy
                                                    ? null
                                                    : () => _editEntry(
                                                          _InvoiceEntry(
                                                            id: doc.id,
                                                            data: data,
                                                            kind: _EntryKind
                                                                .payment,
                                                          ),
                                                        ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: Icon(Icons.delete_outline,
                                                    color: Colors.red.shade700,
                                                    size: 18),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                tooltip: 'حذف',
                                                onPressed: _isBusy
                                                    ? null
                                                    : () => _deleteEntry(
                                                          _InvoiceEntry(
                                                            id: doc.id,
                                                            data: data,
                                                            kind: _EntryKind
                                                                .payment,
                                                          ),
                                                        ),
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

class _ItemDoc {
  final String id;
  final Map<String, dynamic> data;
  double? computedBefore;
  double? computedAfter;

  _ItemDoc({
    required this.id,
    required this.data,
    this.computedBefore,
    this.computedAfter,
  });
}

// ──────────────────────────────────────────────────────────────
// Unified list entry (invoice / return invoice / payment card)
// ──────────────────────────────────────────────────────────────
enum _EntryKind { invoice, returnInvoice, payment }

class _InvoiceEntry {
  final String id;
  final Map<String, dynamic> data;
  final _EntryKind kind;

  _InvoiceEntry({
    required this.id,
    required this.data,
    required this.kind,
  });

  bool get isReturn => kind == _EntryKind.returnInvoice;
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
