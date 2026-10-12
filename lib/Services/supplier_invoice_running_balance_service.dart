import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/balance_history_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/supplier_repository.dart';
import 'invoice_number_utils.dart';

/// The chronological balances displayed on the supplier's invoice page.
class SupplierInvoiceRunningBalanceService {
  SupplierInvoiceRunningBalanceService._();

  static void apply({
    required List<Map<String, dynamic>> invoices,
    required List<Map<String, dynamic>> returns,
    required List<Map<String, dynamic>> payments,
  }) {
    final entries = <_SupplierBalanceEntry>[
      ...invoices.map((data) => _SupplierBalanceEntry(data, 'invoice')),
      ...returns.map((data) => _SupplierBalanceEntry(data, 'return')),
      ...payments.map((data) => _SupplierBalanceEntry(data, 'payment')),
    ]..sort((a, b) => a.date.compareTo(b.date));

    var running = 0.0;
    for (final entry in entries) {
      final data = entry.data;
      data['_computedPrevBalance'] = running;
      if (entry.kind == 'invoice') {
        running += invoiceUnpaidAmount(data);
      } else if (entry.kind == 'return') {
        running -= invoiceUnpaidAmount(data);
      } else {
        final type = data['type']?.toString() ?? '';
        if (type == 'buying_payment' || type == 'return_payment') continue;
        final entered = invoiceNum(
            data['enteredBalance'] ?? data['amount'] ?? data['value']);
        if (type == 'addition' || type == 'buying') {
          running += entered;
        } else if (type == 'deduction' || type == 'return') {
          running -= entered;
        } else if (type == 'opening' || type == 'voucher') {
          final direction = data['direction']?.toString().trim() ?? '';
          final increases =
              type == 'opening' ? direction != 'عليه' : direction == 'له';
          running += increases ? entered : -entered;
        }
      }
      data['_computedRemainingOwed'] = running;
    }
  }

  /// Resolve the same cached invoice and ledger regardless of navigation path.
  static Map<String, dynamic> buildPayload(Map<String, dynamic> raw) {
    final supplierId = raw['supplierId']?.toString().trim() ?? '';
    final supplierName = raw['supplierName']?.toString().trim() ?? '';
    final supplier = (supplierId.isNotEmpty
            ? SupplierRepository.instance.getById(supplierId)
            : null) ??
        SupplierRepository.instance.findByName(supplierName);
    final resolvedId = supplier?.id ?? supplierId;
    if (resolvedId.isEmpty) return Map<String, dynamic>.from(raw);
    final name = supplier?.name ?? supplierName;
    final invoices = InvoiceRepository.instance
        .getBuyingBySupplier(resolvedId, supplierName: name)
        .map((invoice) => invoice.toMap())
        .toList();
    final returns = InvoiceRepository.instance
        .getBuyingReturnsBySupplier(resolvedId, supplierName: name)
        .map((invoice) => invoice.toMap())
        .toList();
    final payments = BalanceHistoryRepository.instance
        .getForSupplier(resolvedId)
        .where((entry) => !{
              'buying',
              'buying_payment',
              'buying_return',
              'buying_return_payment',
              'return',
              'return_payment',
            }.contains(entry.type))
        .map((entry) => entry.toMap())
        .toList();
    final id = (raw['invoiceId'] ?? raw['id'])?.toString() ?? '';
    final isReturn =
        invoiceIsReturn(raw) || raw['invoiceType'] == 'buying_return';
    final candidates = isReturn ? returns : invoices;
    final index = candidates.indexWhere((invoice) => invoice['id'] == id);
    final target =
        index >= 0 ? candidates[index] : Map<String, dynamic>.from(raw);
    if (index < 0) candidates.add(target);
    apply(invoices: invoices, returns: returns, payments: payments);
    return {...raw, ...target, 'supplierId': resolvedId, 'supplierName': name};
  }
}

class _SupplierBalanceEntry {
  final Map<String, dynamic> data;
  final String kind;
  _SupplierBalanceEntry(this.data, this.kind);

  DateTime get date {
    final raw =
        kind == 'payment' ? data['timestamp'] ?? data['date'] : data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      return DateTime.tryParse(raw) ??
          (kind == 'payment' ? DateTime.now() : DateTime(0));
    }
    return kind == 'payment' ? DateTime.now() : DateTime(0);
  }
}
