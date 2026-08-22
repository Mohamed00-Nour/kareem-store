import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/invoice_number_utils.dart';
import '../Services/invoice_stock_service.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';
import '../local_db/models/invoice_local.dart';
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
    final locals = InvoiceRepository.instance.getAllBuying();
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
    _invoicesSubscription = FirebaseFirestore.instance
        .collection('buying invoices')
        .orderBy('date', descending: true)
        .snapshots()
        .listen((querySnapshot) {
      if (!mounted) return;
      setState(() {
        _invoices.clear();
        _invoices.addAll(querySnapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          data['id'] = doc.id; // include Firestore doc ID for editing
          InvoiceRepository.instance.upsertBuyingLocal(doc.id, data);
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
        final supplierName = (invoice['supplierName'] ?? '').toString().toLowerCase();
        final invoiceNumber = (invoice['invoiceNumber'] ?? '').toString();
        final invoiceDate = _parseInvoiceDate(invoice['date']);
        final isInSelectedMonth = _selectedMonth == null ||
            (invoiceDate.year == _selectedMonth!.year &&
                invoiceDate.month == _selectedMonth!.month);
        return (supplierName.contains(query) || invoiceNumber.contains(query)) &&
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
      final products = List<Map<String, dynamic>>.from(
        (removedInvoice['products'] as List?) ?? [],
      );
      final paidAmount = invoiceNum(removedInvoice['paidAmount']);
      final totalSum = invoiceNum(removedInvoice['totalSum']);
      final supplierId = removedInvoice['supplierId']?.toString() ?? '';
      final supplierName = removedInvoice['supplierName']?.toString() ?? '';

      // 1. Decrement stock in Hive (undo purchase)
      if (products.isNotEmpty) {
        await InvoiceStockService.applyStockChanges(
          lines: products,
          restore: false,
          changeDate: DateTime.now(),
          changeTypeWhenDecrease: 'decrease',
        );
      }

      // 2. Delete invoice locally from Hive
      if (invoiceId.isNotEmpty) {
        await InvoiceRepository.instance.deleteBuyingLocal(invoiceId);
      }

      // 3. Delete balance history locally from Hive
      if (supplierId.isNotEmpty && invoiceId.isNotEmpty) {
        await BalanceHistoryRepository.instance
            .deleteByInvoiceId('supplier', supplierId, invoiceId);
      }

      // 4. Adjust Cash Box locally if there was a payment
      if (paidAmount > 0) {
        await BoxRepository.instance.increment(paidAmount);
      }

      // 5. Update supplier balance locally in Hive
      if (supplierId.isNotEmpty) {
        final unpaid = totalSum - paidAmount;
        final localSup = SupplierRepository.instance.getById(supplierId) ??
            SupplierRepository.instance.findByName(supplierName);
        if (localSup != null) {
          await SupplierRepository.instance
              .updateLocalBalance(localSup.id, localSup.balance - unpaid);
        }
      }

      // 6. Enqueue deletion to SyncQueue
      await SyncQueueManager.instance.enqueue(
        operationType: 'deleteBuyingInvoice',
        payload: {
          'supplierId': supplierId,
          'invoiceId': invoiceId,
          'products': products,
          'totalSum': totalSum,
          'paidAmount': paidAmount,
        },
      );

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