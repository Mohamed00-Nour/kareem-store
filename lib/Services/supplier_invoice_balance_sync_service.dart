import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';

enum _SupplierBalanceEventKind {
  buyingInvoice,
  balanceHistoryPayment,
  voucher,
}

class _SupplierBalanceEvent {
  final DateTime date;
  final _SupplierBalanceEventKind kind;
  final Map<String, dynamic> data;

  const _SupplierBalanceEvent({
    required this.date,
    required this.kind,
    required this.data,
  });
}

/// Recomputes supplier [totalBalance] and writes it to [balance] on every
/// buying invoice (المتبقي للمورد — same value on all invoices for that supplier).
class SupplierInvoiceBalanceSyncService {
  static const _maxBatchOps = 450;

  static final _firestore = FirebaseFirestore.instance;

  static Future<void> syncForSupplier(String supplierId) async {
    final trimmed = supplierId.trim();
    if (trimmed.isEmpty) return;

    final supplierRef = _firestore.collection('suppliers').doc(trimmed);
    final supplierSnap = await supplierRef.get();
    if (!supplierSnap.exists) return;

    final results = await Future.wait([
      supplierRef.collection('buying invoices').get(),
      supplierRef.collection('balanceHistory').get(),
      _firestore
          .collection('supplier_vouchers')
          .where('supplierId', isEqualTo: trimmed)
          .get(),
    ]);

    final invoiceDocs = results[0].docs;
    final events = <_SupplierBalanceEvent>[];

    for (final doc in invoiceDocs) {
      final data = doc.data();
      final date = _readEventDate(data);
      if (date == null) continue;
      events.add(_SupplierBalanceEvent(
        date: date,
        kind: _SupplierBalanceEventKind.buyingInvoice,
        data: data,
      ));
    }

    for (final doc in results[1].docs) {
      final data = doc.data();
      final typeStr = data['type']?.toString();
      if (typeStr == 'opening' || typeStr == 'voucher') continue;
      final date = _readEventDate(data, timestampField: 'timestamp');
      if (date == null) continue;
      events.add(_SupplierBalanceEvent(
        date: date,
        kind: _SupplierBalanceEventKind.balanceHistoryPayment,
        data: data,
      ));
    }

    for (final doc in results[2].docs) {
      final data = doc.data();
      final date = _readEventDate(data) ??
          _readEventDate(data, timestampField: 'timestamp');
      if (date == null) continue;
      events.add(_SupplierBalanceEvent(
        date: date,
        kind: _SupplierBalanceEventKind.voucher,
        data: data,
      ));
    }

    events.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.kind.index.compareTo(b.kind.index);
    });

    var running = 0.0;

    for (final event in events) {
      switch (event.kind) {
        case _SupplierBalanceEventKind.buyingInvoice:
          running -= invoiceUnpaidAmount(event.data);
          break;
        case _SupplierBalanceEventKind.balanceHistoryPayment:
          running += invoiceNum(event.data['enteredBalance']);
          break;
        case _SupplierBalanceEventKind.voucher:
          final amount = invoiceNum(event.data['amount']);
          final direction = event.data['direction']?.toString() ?? '';
          if (direction == 'عليه') {
            running += amount;
          } else if (direction == 'له') {
            running -= amount;
          }
          break;
      }
    }

    final hasLedgerEvents = events.isNotEmpty;
    if (!hasLedgerEvents) return;

    final storedBalance =
        invoiceNum(supplierSnap.data()?['totalBalance']);
    final hasOpeningVoucher = events.any((e) =>
        e.kind == _SupplierBalanceEventKind.voucher &&
        e.data['description']?.toString() == 'رصيد افتتاحي');
    if (!hasOpeningVoucher && (storedBalance - running).abs() > 0.001) {
      running = storedBalance;
    }

    await supplierRef.set({'totalBalance': running}, SetOptions(merge: true));

    final fields = <String, dynamic>{'balance': running};

    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    Future<void> flushBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      opCount = 0;
    }

    Future<void> queueUpdate(DocumentReference<Map<String, dynamic>> ref) async {
      batch.update(ref, fields);
      opCount++;
      if (opCount >= _maxBatchOps) {
        await flushBatch();
      }
    }

    for (final doc in invoiceDocs) {
      await queueUpdate(doc.reference);
      final rootId = doc.data()['invoiceId']?.toString();
      if (rootId == null || rootId.isEmpty) continue;
      final rootRef = _firestore.collection('buying invoices').doc(rootId);
      final rootSnap = await rootRef.get();
      if (rootSnap.exists) {
        await queueUpdate(rootRef);
      }
    }

    await flushBatch();
  }

  static DateTime? _readEventDate(
    Map<String, dynamic> data, {
    String timestampField = 'date',
  }) {
    final value = data[timestampField];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
