import 'package:cloud_firestore/cloud_firestore.dart';
import '../sync/connectivity_service.dart';
import '../repositories/client_repository.dart';
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
    // 1. Do not run calculation offline
    if (!ConnectivityService.instance.isOnline) return;

    final trimmed = clientId.trim();
    if (trimmed.isEmpty) return;

    final clientRef = _firestore.collection('clients').doc(trimmed);

    final clientSnap = await clientRef.get();
    if (!clientSnap.exists) return;
    final clientData = clientSnap.data() ?? {};

    final results = await Future.wait([
      clientRef.collection('invoices').get(),
      clientRef.collection('returnInvoices').get(),
      clientRef.collection('balanceHistory').get(),
    ]);

    final saleDocs = results[0].docs;
    final returnDocs = results[1].docs;
    var historyDocs = results[2].docs;

    String canonicalInvoiceId(QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final linkedId = data['invoiceId']?.toString().trim() ?? '';
      if (linkedId.isNotEmpty) return linkedId;
      final storedId = data['id']?.toString().trim() ?? '';
      return storedId.isNotEmpty ? storedId : doc.id;
    }

    String? resolveInvoiceId(
      Iterable<QueryDocumentSnapshot> invoices,
      String historyInvoiceId,
      String historyInvoiceNumber,
    ) {
      for (final invoice in invoices) {
        final data = invoice.data() as Map<String, dynamic>? ?? {};
        final canonicalId = canonicalInvoiceId(invoice);
        final linkedId = data['invoiceId']?.toString().trim() ?? '';
        final storedId = data['id']?.toString().trim() ?? '';
        final invoiceNumber = data['invoiceNumber']?.toString().trim() ?? '';

        if (historyInvoiceId.isNotEmpty &&
            (historyInvoiceId == canonicalId ||
                historyInvoiceId == invoice.id ||
                historyInvoiceId == linkedId ||
                historyInvoiceId == storedId)) {
          return canonicalId;
        }
        if (historyInvoiceNumber.isNotEmpty &&
            invoiceNumber.isNotEmpty &&
            historyInvoiceNumber == invoiceNumber) {
          return canonicalId;
        }
      }
      return null;
    }

    List<QueryDocumentSnapshot> sortAndDeduplicateHistory(
      List<QueryDocumentSnapshot> docs,
    ) {
      final sortedDocs = _sortDocsAscending(docs);
      final seenInvoiceEntries = <String>{};
      return sortedDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final type = data['type']?.toString() ?? '';
        final invId = data['invoiceId']?.toString().trim() ?? '';
        final invNum = data['invoiceNumber']?.toString().trim() ?? '';

        String? resolvedId;
        if (type == 'sale' || type == 'sale_payment') {
          resolvedId = resolveInvoiceId(saleDocs, invId, invNum);
        } else if (type == 'return' || type == 'return_payment') {
          resolvedId = resolveInvoiceId(returnDocs, invId, invNum);
        } else {
          return true;
        }

        final identity = resolvedId ??
            (invNum.isNotEmpty
                ? 'number:$invNum'
                : (invId.isNotEmpty ? 'id:$invId' : 'doc:${doc.id}'));
        return seenInvoiceEntries.add('$identity:$type');
      }).toList();
    }

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

    bool matchesSalesMap(String invId, String invNum) {
      return resolveInvoiceId(saleDocs, invId, invNum) != null;
    }

    bool matchesReturnsMap(String invId, String invNum) {
      return resolveInvoiceId(returnDocs, invId, invNum) != null;
    }

    for (final doc in historyDocs) {
      final data = doc.data();
      final type = data['type']?.toString();
      final invId = data['invoiceId']?.toString() ?? '';
      final invNum = data['invoiceNumber']?.toString() ?? '';

      if (type == 'sale') {
        if (!matchesSalesMap(invId, invNum)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          final resolvedId = resolveInvoiceId(saleDocs, invId, invNum)!;
          historySaleDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'sale_payment') {
        if (!matchesSalesMap(invId, invNum)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          final resolvedId = resolveInvoiceId(saleDocs, invId, invNum)!;
          historySalePaymentDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'return') {
        if (!matchesReturnsMap(invId, invNum)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          final resolvedId = resolveInvoiceId(returnDocs, invId, invNum)!;
          historyReturnDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'return_payment') {
        if (!matchesReturnsMap(invId, invNum)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        } else {
          final resolvedId = resolveInvoiceId(returnDocs, invId, invNum)!;
          historyReturnPaymentDocs.putIfAbsent(resolvedId, () => doc);
        }
      }
    }

    // Align sales invoice records
    for (final doc in saleDocs) {
      final invoiceId = canonicalInvoiceId(doc);
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
        final newDocRef = clientRef.collection('balanceHistory').doc('${invoiceId}_sale');
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
          final newDocRef = clientRef.collection('balanceHistory').doc('${invoiceId}_pay');
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
      final invoiceId = canonicalInvoiceId(doc);
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
    var sorted = sortAndDeduplicateHistory(finalHistoryDocs);

    // If client has an openingBalance field not yet recorded in balanceHistory, create it once
    final double rawOpeningBalance = (clientData['openingBalance'] as num?)?.toDouble() ?? 0.0;
    if (rawOpeningBalance != 0.0 && !sorted.any((d) => (d.data() as Map)['type'] == 'opening')) {
      final openingRef = clientRef.collection('balanceHistory').doc('${trimmed}_opening');
      await openingRef.set({
        'enteredBalance': rawOpeningBalance,
        'balanceBefore': 0.0,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'opening',
      });
      final refreshed = (await clientRef.collection('balanceHistory').get()).docs;
      sorted = sortAndDeduplicateHistory(refreshed);
    }

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

    // Update client balance on main doc and update local cache
    await clientRef.set({'balance': running}, SetOptions(merge: true));
    await ClientRepository.instance.updateLocalBalance(trimmed, running);

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
      final invoiceId = canonicalInvoiceId(doc);
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

      final rootId = canonicalInvoiceId(doc);
      if (rootId.isNotEmpty) {
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
      final invoiceId = canonicalInvoiceId(doc);
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

      final rootId = canonicalInvoiceId(doc);
      if (rootId.isNotEmpty) {
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
