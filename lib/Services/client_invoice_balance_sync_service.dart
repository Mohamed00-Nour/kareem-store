import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';

enum _BalanceEventKind { saleInvoice, returnInvoice, manualPayment }

class _BalanceEvent {
  final DateTime date;
  final _BalanceEventKind kind;
  final Map<String, dynamic> data;

  const _BalanceEvent({
    required this.date,
    required this.kind,
    required this.data,
  });
}

/// Computes the client's current balance and writes it to [balance] on every
/// invoice (المتبقي عليكم — same value on all invoices for that client).
class ClientInvoiceBalanceSyncService {
  static const _maxBatchOps = 450;

  static final _firestore = FirebaseFirestore.instance;

  static Future<void> syncForClient(String clientId) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) return;

    final clientRef = _firestore.collection('clients').doc(trimmed);

    final results = await Future.wait([
      clientRef.collection('invoices').get(),
      clientRef.collection('returnInvoices').get(),
      clientRef.collection('balanceHistory').get(),
    ]);

    final saleDocs = results[0].docs;
    final returnDocs = results[1].docs;

    final events = <_BalanceEvent>[];

    for (final doc in saleDocs) {
      final data = doc.data();
      final date = _readEventDate(data);
      if (date == null) continue;
      events.add(_BalanceEvent(
        date: date,
        kind: _BalanceEventKind.saleInvoice,
        data: data,
      ));
    }

    for (final doc in returnDocs) {
      final data = doc.data();
      final date = _readEventDate(data);
      if (date == null) continue;
      events.add(_BalanceEvent(
        date: date,
        kind: _BalanceEventKind.returnInvoice,
        data: data,
      ));
    }

    for (final doc in results[2].docs) {
      final data = doc.data();
      final type = data['type']?.toString();
      if (type == 'sale' || type == 'return') continue;
      final date = _readEventDate(data, timestampField: 'timestamp');
      if (date == null) continue;
      events.add(_BalanceEvent(
        date: date,
        kind: _BalanceEventKind.manualPayment,
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
        case _BalanceEventKind.saleInvoice:
        case _BalanceEventKind.returnInvoice:
          final unpaid = invoiceUnpaidAmount(event.data);
          if (event.kind == _BalanceEventKind.returnInvoice ||
              invoiceIsReturn(event.data)) {
            running -= unpaid;
          } else {
            running += unpaid;
          }
          break;
        case _BalanceEventKind.manualPayment:
          final entryType = event.data['type']?.toString();
          if (entryType == 'opening') {
            running += invoiceNum(event.data['enteredBalance']);
          } else {
            running -= invoiceNum(event.data['enteredBalance']);
          }
          break;
      }
    }

    await clientRef.set({'balance': running}, SetOptions(merge: true));

    final fields = <String, dynamic>{
      'balance': running,
      'clientBalance': FieldValue.delete(),
    };

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

    Future<void> applyToSubDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String rootCollection,
    ) async {
      for (final doc in docs) {
        await queueUpdate(doc.reference);
        final rootId = doc.data()['invoiceId']?.toString();
        if (rootId == null || rootId.isEmpty) continue;
        final rootRef = _firestore.collection(rootCollection).doc(rootId);
        final rootSnap = await rootRef.get();
        if (rootSnap.exists) {
          await queueUpdate(rootRef);
        }
      }
    }

    await applyToSubDocs(saleDocs, 'invoices');
    await applyToSubDocs(returnDocs, 'returnInvoices');
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
