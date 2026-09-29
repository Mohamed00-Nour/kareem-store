import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../Services/supplier_invoice_balance_sync_service.dart';
import '../repositories/balance_history_repository.dart';
import '../local_db/models/balance_history_local.dart';
import '../sync/connectivity_service.dart';

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
  List<_SupplierHistoryRow> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFromLocalCache();
    _backgroundSync();
  }

  void _loadFromLocalCache() {
    final locals =
        BalanceHistoryRepository.instance.getForSupplier(widget.supplierId);
    double running = 0.0;
    final rows = <_SupplierHistoryRow>[];
    for (final entry in locals) {
      final type = entry.type;
      final direction = entry.direction.trim();
      final isIncrease = type == 'buying' ||
          type == 'addition' ||
          type == 'buying_return_payment' ||
          type == 'return_payment' ||
          (type == 'opening' && direction != 'عليه') ||
          (type == 'voucher' && direction == 'له');
      final before = running;
      running += isIncrease ? entry.enteredBalance : -entry.enteredBalance;
      rows.add(
        _SupplierHistoryRow(
          entry: entry,
          before: before,
          after: running,
          isIncrease: isIncrease,
        ),
      );
    }

    final newestFirst = rows.reversed.toList();
    if (mounted) {
      setState(() {
        _history = newestFirst;
        _isLoading = false;
      });
    }
  }

  Future<void> _backgroundSync() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      await ConnectivityService.instance.forceSync();
      await SupplierInvoiceBalanceSyncService.syncForSupplier(
        widget.supplierId,
      );
      _loadFromLocalCache();
    } catch (_) {
      // The Hive ledger remains authoritative and visible offline.
    }
  }

  String _descriptionForEntry(BalanceHistoryLocal entry) {
    final type = entry.type;
    final direction = entry.direction.trim();
    final invoiceNumber = entry.invoiceNumber;

    if (type == 'opening') {
      return entry.notes.isNotEmpty ? entry.notes : 'رصيد افتتاحي';
    }
    if (type == 'buying') {
      return 'فاتورة مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }
    if (type == 'buying_payment') {
      return 'سداد فاتورة مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }
    if (type == 'buying_return' || type == 'return') {
      return 'فاتورة مرتجع مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }
    if (type == 'buying_return_payment' || type == 'return_payment') {
      return 'تحصيل مرتجع مشتريات' +
          (invoiceNumber.isNotEmpty ? ' رقم $invoiceNumber' : '');
    }

    if (entry.notes.isNotEmpty) return entry.notes;
    if (type == 'addition') return 'إضافة رصيد';
    if (type == 'deduction') return 'خصم رصيد';
    if (type == 'voucher') {
      return direction.isEmpty ? 'سند مورد' : 'سند مورد ($direction)';
    }
    return 'حركة رصيد';
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
                          DataColumn(label: Text('الحركة')),
                          DataColumn(label: Text('الرصيد قبل')),
                          DataColumn(label: Text('الرصيد بعد')),
                          DataColumn(label: Text('التاريخ')),
                        ],
                        rows: _history.map((row) {
                          final entry = row.entry;
                          final formattedDate =
                              DateFormat('yyyy-MM-dd').format(entry.timestamp);
                          final description = _descriptionForEntry(entry);
                          final sign = row.isIncrease ? '+' : '-';

                          return DataRow(cells: [
                            DataCell(Text(description)),
                            DataCell(Text(
                                '$sign${entry.enteredBalance.toStringAsFixed(2)}')),
                            DataCell(Text(row.before.toStringAsFixed(2))),
                            DataCell(Text(row.after.toStringAsFixed(2))),
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

class _SupplierHistoryRow {
  final BalanceHistoryLocal entry;
  final double before;
  final double after;
  final bool isIncrease;

  const _SupplierHistoryRow({
    required this.entry,
    required this.before,
    required this.after,
    required this.isIncrease,
  });
}
