import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';

/// Applies the same chronological client-balance calculation to every invoice
/// map used by the client statement and standalone invoice screens.
class ClientInvoiceRunningBalanceService {
  const ClientInvoiceRunningBalanceService._();

  static void apply({
    required List<Map<String, dynamic>> salesInvoices,
    required List<Map<String, dynamic>> returnInvoices,
    required List<Map<String, dynamic>> payments,
    double initialBalance = 0,
  }) {
    final entries = <_RunningBalanceEntry>[
      ...salesInvoices.map(
        (data) => _RunningBalanceEntry(
          data: data,
          kind: _RunningBalanceEntryKind.invoice,
        ),
      ),
      ...returnInvoices.map(
        (data) => _RunningBalanceEntry(
          data: data,
          kind: _RunningBalanceEntryKind.returnInvoice,
        ),
      ),
      ...payments.map(
        (data) => _RunningBalanceEntry(
          data: data,
          kind: _RunningBalanceEntryKind.payment,
        ),
      ),
    ];

    entries.sort((a, b) {
      final aOpening = a.kind == _RunningBalanceEntryKind.payment &&
          a.data['type'] == 'opening';
      final bOpening = b.kind == _RunningBalanceEntryKind.payment &&
          b.data['type'] == 'opening';
      if (aOpening != bOpening) return aOpening ? -1 : 1;
      final date = _entryDate(a).compareTo(_entryDate(b));
      if (date != 0) return date;
      return (a.data['id']?.toString() ?? '')
          .compareTo(b.data['id']?.toString() ?? '');
    });

    var running = initialBalance;
    for (final entry in entries) {
      final data = entry.data;
      data['_computedPrevBalance'] = running;

      switch (entry.kind) {
        case _RunningBalanceEntryKind.invoice:
          running +=
              invoiceNum(data['totalSum']) - invoiceNum(data['paidAmount']);
          break;
        case _RunningBalanceEntryKind.returnInvoice:
          running -=
              invoiceNum(data['totalSum']) - invoiceNum(data['paidAmount']);
          break;
        case _RunningBalanceEntryKind.payment:
          final type = data['type']?.toString() ?? '';

          // paidAmount is already included in its invoice/return calculation.
          if (type == 'sale_payment' || type == 'return_payment') {
            continue;
          }

          final entered = invoiceNum(
            data['enteredBalance'] ?? data['amount'] ?? data['value'],
          );
          if (type == 'opening' || type == 'addition' || type == 'sale') {
            running += entered;
          } else if (type == 'deduction' || type == 'return') {
            running -= entered;
          }
          break;
      }

      data['_computedRemainingOwed'] = running;
    }
  }

  /// Preserve the accepted opening/carry balance when historical cache is incomplete.
  static double carryForward(
      {required double currentBalance,
      required List<Map<String, dynamic>> salesInvoices,
      required List<Map<String, dynamic>> returnInvoices,
      required List<Map<String, dynamic>> payments}) {
    double net = 0;
    for (final invoice in salesInvoices) net += invoiceUnpaidAmount(invoice);
    for (final invoice in returnInvoices) net -= invoiceUnpaidAmount(invoice);
    for (final payment in payments) {
      final type = payment['type'];
      final amount = invoiceNum(
          payment['enteredBalance'] ?? payment['amount'] ?? payment['value']);
      if (['opening', 'addition', 'sale'].contains(type)) net += amount;
      if (['deduction', 'return'].contains(type)) net -= amount;
    }
    return currentBalance - net;
  }

  static DateTime _entryDate(_RunningBalanceEntry entry) {
    final raw = entry.kind == _RunningBalanceEntryKind.payment
        ? entry.data['timestamp']
        : entry.data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime(0);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime(0);
  }
}

enum _RunningBalanceEntryKind { invoice, returnInvoice, payment }

class _RunningBalanceEntry {
  final Map<String, dynamic> data;
  final _RunningBalanceEntryKind kind;

  const _RunningBalanceEntry({required this.data, required this.kind});
}
