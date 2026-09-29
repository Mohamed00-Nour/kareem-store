import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/supplier_operation_service.dart';
import '../repositories/invoice_repository.dart';
import '../sync/connectivity_service.dart';
import 'BuyingInvoiceDetailPage.dart';

class BuyingInvoiceListPage extends StatefulWidget {
  const BuyingInvoiceListPage({super.key});

  @override
  _BuyingInvoiceListPageState createState() => _BuyingInvoiceListPageState();
}

class _BuyingInvoiceListPageState extends State<BuyingInvoiceListPage> {
  final List<Map<String, dynamic>> _invoices = [];
  final List<Map<String, dynamic>> _filteredInvoices = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isFetching = true;
  DateTime? _selectedMonth;
  String _userRole = 'user'; // Default to user role

  @override
  void initState() {
    super.initState();
    // Initialize with current month
    _selectedMonth = DateTime.now();
    _loadUserRole();
    _loadFromLocalCache();
    _backgroundSyncInvoices();
    _searchController.addListener(_filterInvoices);
  }

  void _loadFromLocalCache() {
    final locals = InvoiceRepository.instance.getAllBuying();
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
      await InvoiceRepository.instance.deltaSyncBuying();
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

  void _handleDeleteAction(int index) {
    if (_userRole == 'admin') {
      _showDeleteConfirmationDialog(index);
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showDeleteConfirmationDialog(int index) {
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
                _deleteInvoice(index);
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

  void _deleteInvoice(int index) async {
    final removedInvoice = _filteredInvoices.removeAt(index);
    final invoiceId = removedInvoice['id']?.toString() ??
        removedInvoice['invoiceId']?.toString() ??
        '';

    setState(() {});

    try {
      if (invoiceId.isEmpty) throw StateError('معرف الفاتورة غير موجود');
      await SupplierOperationService.deleteBuyingInvoice(invoiceId);
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
      setState(() {
        _filteredInvoices.insert(index, removedInvoice);
      });
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
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
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
                return Card(
                  color: Colors.orange.withOpacity(0.8),
                  elevation: 2,
                  child: ListTile(
                    title: Center(
                        child: Text('فاتورة #${invoice['invoiceNumber']}')),
                    subtitle: Center(
                        child: Text('المورد: ${invoice['supplierName']}')),
                    trailing: IconButton(
                      icon: Icon(Icons.delete,
                          color: Colors.black.withOpacity(0.7)),
                      onPressed: () => _handleDeleteAction(index),
                    ),
                    onTap: () => _navigateToInvoiceDetail(invoice),
                  ),
                );
              },
            ),
    );
  }
}
