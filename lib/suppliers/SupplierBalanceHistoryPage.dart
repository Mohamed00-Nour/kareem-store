import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../repositories/balance_history_repository.dart';
import '../local_db/models/balance_history_local.dart';

class SupplierBalanceHistoryPage extends StatefulWidget {
  final String supplierId;

  const SupplierBalanceHistoryPage({Key? key, required this.supplierId})
      : super(key: key);

  @override
  State<SupplierBalanceHistoryPage> createState() =>
      _SupplierBalanceHistoryPageState();
}

class _SupplierBalanceHistoryPageState
    extends State<SupplierBalanceHistoryPage> {
  List<BalanceHistoryLocal> _history = [];
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _loadFromLocalCache();
    _listenToHistory();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _loadFromLocalCache() {
    final locals =
        BalanceHistoryRepository.instance.getForSupplier(widget.supplierId);
    locals.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    double running = 0.0;
    final Map<String, double> beforeMap = {};
    for (final entry in locals) {
      beforeMap[entry.id] = running;
      final type = entry.type;
      final isIncrease = type == 'buying' || type == 'opening' || type == 'addition';
      if (isIncrease) {
        running += entry.enteredBalance;
      } else {
        running -= entry.enteredBalance;
      }
    }

    locals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (mounted) {
      setState(() {
        _history = locals;
        _isLoading = false;
      });
    }
  }

  void _listenToHistory() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('suppliers')
        .doc(widget.supplierId)
        .collection('balanceHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final entry = BalanceHistoryLocal.fromFirestore(
          doc.id,
          widget.supplierId,
          'supplier',
          data,
        );
        await BalanceHistoryRepository.instance.upsertLocal(entry);
      }
      _loadFromLocalCache();
    }, onError: (_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String _descriptionForEntry(BalanceHistoryLocal entry) {
    final type = entry.type;
    final notes = entry.direction.isNotEmpty ? entry.direction : '';
    final invoiceNumber = entry.invoiceNumber;

    if (type == 'opening') {
      return 'رصيد افتتاحي';
    }
    if (type == 'buying') {
      return 'فاتورة مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }
    if (type == 'buying_payment') {
      return 'سداد فاتورة مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }

    String description = '';
    if (type == 'voucher') {
      description = 'سند';
    } else {
      description = 'سداد نقدي';
    }

    if (notes.isNotEmpty) {
      description += ' ($notes)';
    }
    return description;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاريخ الرصيد'),
        backgroundColor: Colors.black.withOpacity(0.7),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Text(
                    'لا يوجد سجلات لتاريخ الرصيد',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('البيان')),
                          DataColumn(label: Text('الرصيد المدخل')),
                          DataColumn(label: Text('الرصيد قبل')),
                          DataColumn(label: Text('التاريخ')),
                        ],
                        rows: _history.map((entry) {
                          final formattedDate = DateFormat('yyyy-MM-dd')
                              .format(entry.timestamp);
                          final description = _descriptionForEntry(entry);

                          return DataRow(cells: [
                            DataCell(Text(description)),
                            DataCell(Text(
                                entry.enteredBalance.toStringAsFixed(2))),
                            DataCell(Text(
                                entry.balanceBefore.toStringAsFixed(2))),
                            DataCell(Text(formattedDate)),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
    );
  }
}