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

    entries.sort((a, b) => _entryDate(a).compareTo(_entryDate(b)));

    var running = 0.0;
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

  static DateTime _entryDate(_RunningBalanceEntry entry) {
    final raw = entry.kind == _RunningBalanceEntryKind.payment
        ? entry.data['timestamp']
        : entry.data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime(0);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return entry.kind == _RunningBalanceEntryKind.payment
        ? DateTime.now()
        : DateTime(0);
  }
}

enum _RunningBalanceEntryKind { invoice, returnInvoice, payment }

class _RunningBalanceEntry {
  final Map<String, dynamic> data;
  final _RunningBalanceEntryKind kind;

  const _RunningBalanceEntry({required this.data, required this.kind});
}
