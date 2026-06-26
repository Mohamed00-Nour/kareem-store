import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoice_number_utils.dart';

class ClientInvoiceBalanceSyncService {
  static const _maxBatchOps = 450;
  static final _firestore = FirebaseFirestore.instance;

  static int _typePriority(String type) {
    switch (type) {
      case 'opening':
        return 0;
      case 'sale':
        return 1;
      case 'sale_payment':
        return 2;
      case 'return':
        return 3;
      case 'return_payment':
        return 4;
      case 'addition':
        return 5;
      case 'deduction':
        return 6;
      default:
        return 7;
    }
  }

  static List<QueryDocumentSnapshot> _sortDocsAscending(List<QueryDocumentSnapshot> docs) {
    final sorted = List<QueryDocumentSnapshot>.from(docs);
    sorted.sort((a, b) {
      final dataA = a.data() as Map<String, dynamic>;
      final dataB = b.data() as Map<String, dynamic>;
      final typeA = dataA['type']?.toString() ?? '';
      final typeB = dataB['type']?.toString() ?? '';

      // Opening always first
      if (typeA == 'opening' && typeB != 'opening') return -1;
      if (typeB == 'opening' && typeA != 'opening') return 1;

      // Group by same invoiceId
      final invA = dataA['invoiceId']?.toString() ?? '';
      final invB = dataB['invoiceId']?.toString() ?? '';
      if (invA.isNotEmpty && invA == invB) {
        return _typePriority(typeA).compareTo(_typePriority(typeB));
      }

      // Then by timestamp ascending (oldest first)
      final tsA = dataA['timestamp'];
      final tsB = dataB['timestamp'];
      DateTime? dateA, dateB;
      if (tsA is Timestamp) dateA = tsA.toDate();
      if (tsB is Timestamp) dateB = tsB.toDate();

      if (dateA != null && dateB != null) {
        final cmp = dateA.compareTo(dateB);
        if (cmp != 0) return cmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }

      return _typePriority(typeA).compareTo(_typePriority(typeB));
    });
    return sorted;
  }

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
    final historyDocs = results[2].docs;

    final Map<String, DocumentSnapshot> salesMap = {
      for (var doc in saleDocs) doc.id: doc
    };
    final Map<String, DocumentSnapshot> returnsMap = {
      for (var doc in returnDocs) doc.id: doc
    };

    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    Future<void> commitBatchIfNeeded() async {
      if (opCount >= _maxBatchOps) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    final Map<String, QueryDocumentSnapshot> historySaleDocs = {};
    final Map<String, QueryDocumentSnapshot> historySalePaymentDocs = {};
    final Map<String, QueryDocumentSnapshot> historyReturnDocs = {};
    final Map<String, QueryDocumentSnapshot> historyReturnPaymentDocs = {};

    for (final doc in historyDocs) {
      final data = doc.data();
      final type = data['type']?.toString();
      final invId = data['invoiceId']?.toString() ?? '';

      if (type == 'sale') {
        if (!salesMap.containsKey(invId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          historySaleDocs[invId] = doc;
        }
      } else if (type == 'sale_payment') {
        if (!salesMap.containsKey(invId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          historySalePaymentDocs[invId] = doc;
        }
      } else if (type == 'return') {
        if (!returnsMap.containsKey(invId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          historyReturnDocs[invId] = doc;
        }
      } else if (type == 'return_payment') {
        if (!returnsMap.containsKey(invId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          historyReturnPaymentDocs[invId] = doc;
        }
      }
    }

    // Align sales invoice records
    for (final doc in saleDocs) {
      final invoiceId = doc.id;
      final data = doc.data();
      final totalSum = invoiceNum(data['totalSum']);
      final paidAmount = invoiceNum(data['paidAmount']);
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
      final timestamp = data['date'] ?? FieldValue.serverTimestamp();

      if (historySaleDocs.containsKey(invoiceId)) {
        final hDoc = historySaleDocs[invoiceId]!;
        final hData = hDoc.data() as Map<String, dynamic>;
        final hAmount = invoiceNum(hData['enteredBalance']);
        if ((hAmount - totalSum).abs() > 0.001) {
          batch.update(hDoc.reference, {'enteredBalance': totalSum});
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        final newDocRef = clientRef.collection('balanceHistory').doc();
        batch.set(newDocRef, {
          'enteredBalance': totalSum,
          'balanceBefore': 0.0,
          'timestamp': timestamp,
          'type': 'sale',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
        opCount++;
        await commitBatchIfNeeded();
      }

      if (paidAmount > 0) {
        if (historySalePaymentDocs.containsKey(invoiceId)) {
          final hDoc = historySalePaymentDocs[invoiceId]!;
          final hData = hDoc.data() as Map<String, dynamic>;
          final hAmount = invoiceNum(hData['enteredBalance']);
          if ((hAmount - paidAmount).abs() > 0.001) {
            batch.update(hDoc.reference, {'enteredBalance': paidAmount});
            opCount++;
            await commitBatchIfNeeded();
          }
        } else {
          final newDocRef = clientRef.collection('balanceHistory').doc();
          batch.set(newDocRef, {
            'enteredBalance': paidAmount,
            'balanceBefore': 0.0,
            'timestamp': timestamp,
            'type': 'sale_payment',
            'invoiceId': invoiceId,
            'invoiceNumber': invoiceNumber,
          });
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        if (historySalePaymentDocs.containsKey(invoiceId)) {
          batch.delete(historySalePaymentDocs[invoiceId]!.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      }
    }

    // Align return invoice records
    for (final doc in returnDocs) {
      final invoiceId = doc.id;
      final data = doc.data();
      final totalSum = invoiceNum(data['totalSum']);
      final paidAmount = invoiceNum(data['paidAmount']);
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
      final timestamp = data['date'] ?? FieldValue.serverTimestamp();

      if (historyReturnDocs.containsKey(invoiceId)) {
        final hDoc = historyReturnDocs[invoiceId]!;
        final hData = hDoc.data() as Map<String, dynamic>;
        final hAmount = invoiceNum(hData['enteredBalance']);
        if ((hAmount - totalSum).abs() > 0.001) {
          batch.update(hDoc.reference, {'enteredBalance': totalSum});
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        final newDocRef = clientRef.collection('balanceHistory').doc();
        batch.set(newDocRef, {
          'enteredBalance': totalSum,
          'balanceBefore': 0.0,
          'timestamp': timestamp,
          'type': 'return',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
        opCount++;
        await commitBatchIfNeeded();
      }

      if (paidAmount > 0) {
        if (historyReturnPaymentDocs.containsKey(invoiceId)) {
          final hDoc = historyReturnPaymentDocs[invoiceId]!;
          final hData = hDoc.data() as Map<String, dynamic>;
          final hAmount = invoiceNum(hData['enteredBalance']);
          if ((hAmount - paidAmount).abs() > 0.001) {
            batch.update(hDoc.reference, {'enteredBalance': paidAmount});
            opCount++;
            await commitBatchIfNeeded();
          }
        } else {
          final newDocRef = clientRef.collection('balanceHistory').doc();
          batch.set(newDocRef, {
            'enteredBalance': paidAmount,
            'balanceBefore': 0.0,
            'timestamp': timestamp,
            'type': 'return_payment',
            'invoiceId': invoiceId,
            'invoiceNumber': invoiceNumber,
          });
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        if (historyReturnPaymentDocs.containsKey(invoiceId)) {
          batch.delete(historyReturnPaymentDocs[invoiceId]!.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    // Refresh history documents to get the final aligned state
    final finalHistoryDocs = (await clientRef.collection('balanceHistory').get()).docs;
    final sorted = _sortDocsAscending(finalHistoryDocs);

    var running = 0.0;
    final Map<String, double> invPreviousBalances = {};
    final Map<String, double> invAfterBalances = {};
    WriteBatch recalculateBatch = _firestore.batch();
    var recCount = 0;

    for (final doc in sorted) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString() ?? '';
      final entered = invoiceNum(data['enteredBalance']);
      final currentBefore = invoiceNum(data['balanceBefore']);
      final invId = data['invoiceId']?.toString() ?? '';

      if ((currentBefore - running).abs() > 0.001) {
        recalculateBatch.update(doc.reference, {'balanceBefore': running});
        recCount++;
        if (recCount >= _maxBatchOps) {
          await recalculateBatch.commit();
          recalculateBatch = _firestore.batch();
          recCount = 0;
        }
      }

      final isIncrease = type == 'sale' ||
          type == 'addition' ||
          type == 'opening' ||
          type == 'return_payment';

      if (invId.isNotEmpty) {
        if (type == 'sale' || type == 'return') {
          invPreviousBalances[invId] = running;
        }
      }

      if (isIncrease) {
        running += entered;
      } else {
        running -= entered;
      }

      if (invId.isNotEmpty) {
        invAfterBalances[invId] = running;
      }
    }

    if (recCount > 0) {
      await recalculateBatch.commit();
    }

    // Update client balance on main doc
    await clientRef.set({'balance': running}, SetOptions(merge: true));

    WriteBatch finalBatch = _firestore.batch();
    var finalOpCount = 0;

    Future<void> commitFinalBatchIfNeeded() async {
      if (finalOpCount >= _maxBatchOps) {
        await finalBatch.commit();
        finalBatch = _firestore.batch();
        finalOpCount = 0;
      }
    }

    for (final doc in saleDocs) {
      final invoiceId = doc.id;
      final prevBal = invPreviousBalances[invoiceId] ?? 0.0;
      final afterBal = invAfterBalances[invoiceId] ?? 0.0;

      final clientInvoicesFields = <String, dynamic>{
        'previousBalance': prevBal,
        'balance': afterBal,
        'clientBalance': FieldValue.delete(),
      };

      finalBatch.update(doc.reference, clientInvoicesFields);
      finalOpCount++;
      await commitFinalBatchIfNeeded();

      final rootId = doc.data()['invoiceId']?.toString();
      if (rootId != null && rootId.isNotEmpty) {
        final rootRef = _firestore.collection('invoices').doc(rootId);
        final rootSnap = await rootRef.get();
        if (rootSnap.exists) {
          finalBatch.update(rootRef, clientInvoicesFields);
          finalOpCount++;
          await commitFinalBatchIfNeeded();
        }
      }
    }

    for (final doc in returnDocs) {
      final invoiceId = doc.id;
      final prevBal = invPreviousBalances[invoiceId] ?? 0.0;
      final afterBal = invAfterBalances[invoiceId] ?? 0.0;

      final clientInvoicesFields = <String, dynamic>{
        'previousBalance': prevBal,
        'balance': afterBal,
        'clientBalance': FieldValue.delete(),
      };

      finalBatch.update(doc.reference, clientInvoicesFields);
      finalOpCount++;
      await commitFinalBatchIfNeeded();

      final rootId = doc.data()['invoiceId']?.toString();
      if (rootId != null && rootId.isNotEmpty) {
        final rootRef = _firestore.collection('returnInvoices').doc(rootId);
        final rootSnap = await rootRef.get();
        if (rootSnap.exists) {
          finalBatch.update(rootRef, clientInvoicesFields);
          finalOpCount++;
          await commitFinalBatchIfNeeded();
        }
      }
    }

    if (finalOpCount > 0) {
      await finalBatch.commit();
    }
  }
}
