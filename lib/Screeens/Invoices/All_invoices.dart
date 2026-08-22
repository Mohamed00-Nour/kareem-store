import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Services/invoice_special_service.dart';
import '../../Services/sales_invoice_actions_service.dart';
import '../../repositories/invoice_repository.dart';
import '../../local_db/models/invoice_local.dart';
import 'InvoiceDetailPage.dart';

class InvoiceListPage extends StatefulWidget {
  final String collection;
  final String pageTitle;

  const InvoiceListPage({
    super.key,
    this.collection = 'invoices',
    this.pageTitle = 'فواتير المبيعات',
  });

  @override
  _InvoiceListPageState createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  final List<Map<String, dynamic>> _invoices = [];
  final List<Map<String, dynamic>> _filteredInvoices = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isFetching = true;
  DateTime? _selectedMonth;
  String _userRole = 'user'; // Default to user role
  StreamSubscription<QuerySnapshot>? _invoicesSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize with current month
    _selectedMonth = DateTime.now();
    _loadUserRole();
    _loadFromLocalCache();
    _listenToInvoices();
    _searchController.addListener(_filterInvoices);
  }

  void _loadFromLocalCache() {
    List<InvoiceLocal> locals;
    if (widget.collection == 'returnInvoices') {
      locals = InvoiceRepository.instance.getAllReturns();
    } else if (widget.collection == 'buying invoices') {
      locals = InvoiceRepository.instance.getAllBuying();
    } else {
      locals = InvoiceRepository.instance.getAllSales();
    }
    if (locals.isNotEmpty && mounted) {
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
    _invoicesSubscription?.cancel();
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

  void _listenToInvoices() {
    // Cancel any previous subscription in case it's re-initialized
    _invoicesSubscription?.cancel();
    _invoicesSubscription = FirebaseFirestore.instance
        .collection(widget.collection)
        .orderBy('date', descending: true)
        .snapshots()
        .listen((querySnapshot) {
      if (!mounted) return;
      setState(() {
        _invoices.clear();
        _invoices.addAll(querySnapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          data['id'] = doc.id;
          if (widget.collection == 'returnInvoices') {
            InvoiceRepository.instance.upsertReturnLocal(doc.id, data);
          } else if (widget.collection == 'buying invoices') {
            InvoiceRepository.instance.upsertBuyingLocal(doc.id, data);
          } else {
            InvoiceRepository.instance.upsertSaleLocal(doc.id, data);
          }
          return data;
        }));
        _filterInvoices(); // Apply filtering after fetching
        _isFetching = false;
      });
    }, onError: (e) {
      print('Error listening to invoices: $e');
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    });
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
        final clientName = (invoice['clientName'] ?? '').toString().toLowerCase();
        final invoiceNumber = (invoice['invoiceNumber'] ?? '').toString();
        final invoiceDate = _parseInvoiceDate(invoice['date']);
        final isInSelectedMonth = _selectedMonth == null ||
            (invoiceDate.year == _selectedMonth!.year &&
                invoiceDate.month == _selectedMonth!.month);
        return (clientName.contains(query) || invoiceNumber.contains(query)) &&
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
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('اختر الشهر والسنة', style: TextStyle(fontSize: 20.sp)),
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
                    Navigator.of(context).pop(DateTime(selectedYear, selectedMonth));
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

  Future<void> _navigateToInvoiceDetail(Map<String, dynamic> invoice) async {
    final payload = Map<String, dynamic>.from(invoice);
    payload['_sourceCollection'] = widget.collection;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceDetailPage(invoice: payload),
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
      if (invoiceId.isNotEmpty) {
        await SalesInvoiceActionsService.deleteSalesInvoice(
          invoice: removedInvoice,
          rootInvoiceId: invoiceId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الفاتورة بنجاح وإرجاع المنتجات للمخزون'),
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
                final special = InvoiceSpecialService.isSpecial(invoice);
                return Card(
                  color: special
                      ? Colors.amber.shade100
                      : Colors.orange.withOpacity(0.8),
                  elevation: 2,
                  child: ListTile(
                    leading: special
                        ? Icon(Icons.star, color: Colors.amber.shade800)
                        : null,
                    title: Center(
                        child: Text('فاتورة #${invoice['invoiceNumber']}')),
                    subtitle: Center(
                        child: Text('العميل: ${invoice['clientName']}')),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.black.withOpacity(0.7)),
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