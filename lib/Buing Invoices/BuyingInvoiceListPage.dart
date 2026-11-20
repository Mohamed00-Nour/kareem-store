import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screeens/AddProductPage.dart';
import '../Services/supplier_operation_service.dart';
import '../local_db/hive_init.dart';
import '../Services/invoice_number_utils.dart';
import '../repositories/invoice_repository.dart';
import '../sync/connectivity_service.dart';
import 'BuyingInvoiceDetailPage.dart';

class BuyingInvoiceListPage extends StatefulWidget {
  /// Opens on purchase returns (مرتجع المشتريات) instead of purchases.
  final bool showReturns;

  const BuyingInvoiceListPage({super.key, this.showReturns = false});

  @override
  _BuyingInvoiceListPageState createState() => _BuyingInvoiceListPageState();
}

class _BuyingInvoiceListPageState extends State<BuyingInvoiceListPage> {
  final List<Map<String, dynamic>> _invoices = [];
  final List<Map<String, dynamic>> _filteredInvoices = [];
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _invoicesSubscription;
  bool _isFetching = true;
  DateTime? _selectedMonth;
  String _userRole = 'user'; // Default to user role
  late bool _showReturns = widget.showReturns;

  @override
  void initState() {
    super.initState();
    // Initialize with current month
    _selectedMonth = DateTime.now();
    _watchCurrentBox();
    _loadUserRole();
    _loadFromLocalCache();
    _backgroundSyncInvoices();
    _searchController.addListener(_filterInvoices);
  }

  void _watchCurrentBox() {
    _invoicesSubscription?.cancel();
    final box = _showReturns ? buyingReturnInvoicesBox : buyingInvoicesBox;
    _invoicesSubscription = box.watch().listen((_) => _loadFromLocalCache());
  }

  void _toggleReturns() {
    setState(() => _showReturns = !_showReturns);
    _watchCurrentBox();
    _loadFromLocalCache();
  }

  void _loadFromLocalCache() {
    final locals = _showReturns
        ? InvoiceRepository.instance.getAllBuyingReturns()
        : InvoiceRepository.instance.getAllBuying();
    if (mounted) {
      setState(() {
        _invoices.clear();
        _invoices.addAll(locals.map((inv) => inv.toMap()));
        _filterInvoices();
        _isFetching = false;
      });
    }
  }

  @override
  void dispose() {
    _invoicesSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _userRole = prefs.getString('user_role') ?? 'user';
      });
    } catch (e) {
      print('Error loading user role: $e');
    }
  }

  Future<void> _backgroundSyncInvoices() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      await ConnectivityService.instance.forceSync();
      // Purchase returns arrive through the financial receipt feed.
      if (!_showReturns) await InvoiceRepository.instance.deltaSyncBuying();
      _loadFromLocalCache();
    } catch (e) {
      debugPrint('Error syncing buying invoices: $e');
    }
  }

  DateTime _parseInvoiceDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  void _filterInvoices() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredInvoices.clear();
      final filtered = _invoices.where((invoice) {
        final supplierName =
            (invoice['supplierName'] ?? '').toString().toLowerCase();
        final invoiceNumber = (invoice['invoiceNumber'] ?? '').toString();
        final invoiceDate = _parseInvoiceDate(invoice['date']);
        final isInSelectedMonth = _selectedMonth == null ||
            (invoiceDate.year == _selectedMonth!.year &&
                invoiceDate.month == _selectedMonth!.month);
        return (supplierName.contains(query) ||
                invoiceNumber.contains(query)) &&
            isInSelectedMonth;
      }).toList();

      filtered.sort((a, b) {
        final numA = (a['invoiceNumber'] as num?)?.toInt() ?? 0;
        final numB = (b['invoiceNumber'] as num?)?.toInt() ?? 0;
        if (numA > 0 && numB > 0 && numA != numB) {
          return numB.compareTo(numA);
        }
        final dateA = _parseInvoiceDate(a['date']);
        final dateB = _parseInvoiceDate(b['date']);
        final dateComp = dateB.compareTo(dateA);
        if (dateComp != 0) return dateComp;
        return numB.compareTo(numA);
      });

      _filteredInvoices.addAll(filtered);
    });
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await _showMonthYearPicker(context);
    if (picked != null && picked != _selectedMonth) {
      if (!mounted) return;
      setState(() {
        _selectedMonth = picked;
        _filterInvoices();
      });
    }
  }

  Future<DateTime?> _showMonthYearPicker(BuildContext context) async {
    DateTime now = DateTime.now();
    int selectedYear = _selectedMonth?.year ?? now.year;
    int selectedMonth = _selectedMonth?.month ?? now.month;

    // List of Arabic month names
    List<String> arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title:
                  Text('اختر الشهر والسنة', style: TextStyle(fontSize: 20.sp)),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DropdownButton<int>(
                    value: selectedMonth,
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text(arabicMonths[index]),
                      );
                    }),
                    onChanged: (value) {
                      setState(() {
                        selectedMonth = value!;
                      });
                    },
                  ),
                  DropdownButton<int>(
                    value: selectedYear,
                    items: List.generate(50, (index) {
                      return DropdownMenuItem(
                        value: now.year - index,
                        child: Text((now.year - index).toString()),
                      );
                    }),
                    onChanged: (value) {
                      setState(() {
                        selectedYear = value!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('إلغاء'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pop(DateTime(selectedYear, selectedMonth));
                  },
                  child: Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToInvoiceDetail(Map<String, dynamic> invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BuyingInvoiceDetailPage(invoice: invoice),
      ),
    );
  }

  void _handleDeleteAction(Map<String, dynamic> invoice) {
    if (_userRole == 'admin') {
      _showDeleteConfirmationDialog(invoice);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showDeleteConfirmationDialog(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('تأكيد الحذف'),
          content: Text('هل أنت متأكد أنك تريد حذف هذه الفاتورة؟'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteInvoice(invoice);
              },
              child: Text('حذف'),
            ),
          ],
        );
      },
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

  void _deleteInvoice(Map<String, dynamic> invoice) async {
    final invoiceId =
        invoice['id']?.toString() ?? invoice['invoiceId']?.toString() ?? '';

    try {
      if (invoiceId.isEmpty) throw StateError('معرف الفاتورة غير موجود');
      if (invoiceIsBuyingReturn(invoice)) {
        await SupplierOperationService.deleteBuyingReturn(invoiceId);
      } else {
        await SupplierOperationService.deleteBuyingInvoice(invoiceId);
      }
      ConnectivityService.instance.forceSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الفاتورة بنجاح وتحديث المخزون'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error deleting invoice: $e');
      if (!mounted) return;
      _loadFromLocalCache();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء حذف الفاتورة: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '...ابحث عن فاتورة',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            border: InputBorder.none,
          ),
          style: TextStyle(color: Colors.white, fontSize: 20.sp),
        ),
        backgroundColor:
            _showReturns ? Colors.red.shade900 : Colors.black.withOpacity(0.7),
        actions: [
          if (_showReturns)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              tooltip: 'مرتجع مشتريات جديد',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddProductPage(isPurchaseReturn: true),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              _showReturns ? Icons.receipt_long : Icons.assignment_return,
              color: Colors.white,
            ),
            tooltip:
                _showReturns ? 'عرض فواتير المشتريات' : 'عرض مرتجع المشتريات',
            onPressed: _toggleReturns,
          ),
          IconButton(
            icon: Icon(Icons.calendar_month, color: Colors.white),
            onPressed: () => _selectMonth(context),
          ),
        ],
      ),
      body: _isFetching
          ? Center(
              child: CircularProgressIndicator(
                color: Colors.orange.withOpacity(0.8),
              ),
            )
          : ListView.builder(
              itemCount: _filteredInvoices.length,
              itemBuilder: (context, index) {
                final invoice = _filteredInvoices[index];
                final isReturn = invoiceIsBuyingReturn(invoice);
                return Card(
                  color: isReturn
                      ? Colors.red.shade100
                      : Colors.orange.withOpacity(0.8),
                  elevation: 2,
                  child: ListTile(
                    title: Center(
                        child: Text(isReturn
                            ? 'مرتجع #${invoice['invoiceNumber']}'
                            : 'فاتورة #${invoice['invoiceNumber']}')),
                    subtitle: Center(
                        child: Text('المورد: ${invoice['supplierName']}')),
                    trailing: IconButton(
                      icon: Icon(Icons.delete,
                          color: Colors.black.withOpacity(0.7)),
                      onPressed: () => _handleDeleteAction(invoice),
                    ),
                    onTap: () => _navigateToInvoiceDetail(invoice),
                  ),
                );
              },
            ),
    );
  }
}
