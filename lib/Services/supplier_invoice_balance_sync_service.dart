import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoice_number_utils.dart';

class SupplierInvoiceBalanceSyncService {
  static const _maxBatchOps = 450;
  static final _firestore = FirebaseFirestore.instance;

  static int _typePriority(String type) {
    switch (type) {
      case 'opening':
        return 0;
      case 'buying':
        return 1;
      case 'buying_payment':
        return 2;
      case 'voucher':
        return 3;
      default:
        return 4;
    }
  }

  static List<QueryDocumentSnapshot> _sortDocsAscending(
      List<QueryDocumentSnapshot> docs) {
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

    final buyingDocs = results[0].docs;
    final historyDocs = results[1].docs;
    final voucherDocs = results[2].docs;

    final Map<String, DocumentSnapshot> buyingMap = {
      for (var doc in buyingDocs) doc.id: doc
    };
    final Map<String, DocumentSnapshot> vouchersMap = {
      for (var doc in voucherDocs) doc.id: doc
    };

    final Map<String, QueryDocumentSnapshot> historyBuyingDocs = {};
    final Map<String, QueryDocumentSnapshot> historyBuyingPaymentDocs = {};
    final Map<String, QueryDocumentSnapshot> historyVoucherDocs = {};

    for (final doc in historyDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString();
      final invId = data['invoiceId']?.toString() ?? '';
      final vId = data['voucherId']?.toString() ?? '';

      if (type == 'buying') {
        if (!buyingMap.containsKey(invId)) {
          // Will delete later in clean phase
        } else {
          historyBuyingDocs[invId] = doc;
        }
      } else if (type == 'buying_payment') {
        if (!buyingMap.containsKey(invId)) {
          // Will delete later
        } else {
          historyBuyingPaymentDocs[invId] = doc;
        }
      } else if (type == 'voucher' || type == 'opening') {
        if (vId.isNotEmpty && vouchersMap.containsKey(vId)) {
          historyVoucherDocs[vId] = doc;
        }
      }
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

    // Align buying invoice records
    for (final doc in buyingDocs) {
      final invoiceId = doc.id;
      final data = doc.data() as Map<String, dynamic>;
      final totalSum = invoiceNum(data['totalSum']);
      final paidAmount = invoiceNum(data['paidAmount']);
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
      final timestamp = data['date'] ?? FieldValue.serverTimestamp();

      if (historyBuyingDocs.containsKey(invoiceId)) {
        final hDoc = historyBuyingDocs[invoiceId]!;
        final hData = hDoc.data() as Map<String, dynamic>;
        final hAmount = invoiceNum(hData['enteredBalance']);
        if ((hAmount - totalSum).abs() > 0.001) {
          batch.update(hDoc.reference, {'enteredBalance': totalSum});
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        final newDocRef = supplierRef.collection('balanceHistory').doc();
        batch.set(newDocRef, {
          'enteredBalance': totalSum,
          'balanceBefore': 0.0,
          'timestamp': timestamp,
          'type': 'buying',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
        opCount++;
        await commitBatchIfNeeded();
      }

      if (paidAmount > 0) {
        if (historyBuyingPaymentDocs.containsKey(invoiceId)) {
          final hDoc = historyBuyingPaymentDocs[invoiceId]!;
          final hData = hDoc.data() as Map<String, dynamic>;
          final hAmount = invoiceNum(hData['enteredBalance']);
          if ((hAmount - paidAmount).abs() > 0.001) {
            batch.update(hDoc.reference, {'enteredBalance': paidAmount});
            opCount++;
            await commitBatchIfNeeded();
          }
        } else {
          final newDocRef = supplierRef.collection('balanceHistory').doc();
          batch.set(newDocRef, {
            'enteredBalance': paidAmount,
            'balanceBefore': 0.0,
            'timestamp': timestamp,
            'type': 'buying_payment',
            'invoiceId': invoiceId,
            'invoiceNumber': invoiceNumber,
          });
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        if (historyBuyingPaymentDocs.containsKey(invoiceId)) {
          batch.delete(historyBuyingPaymentDocs[invoiceId]!.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      }
    }

    // Align supplier_vouchers
    for (final doc in voucherDocs) {
      final voucherId = doc.id;
      final data = doc.data() as Map<String, dynamic>;
      final amount = invoiceNum(data['amount']);
      final direction = data['direction']?.toString() ?? 'عليه';
      final description = data['description']?.toString() ?? '';
      final voucherNumber = data['voucherNumber']?.toString() ?? '';
      final timestamp =
          data['date'] ?? data['timestamp'] ?? FieldValue.serverTimestamp();

      final isOpening = description == 'رصيد افتتاحي';
      final noteStr = description.trim();

      if (isOpening) {
        // Find if there is an existing opening doc in history
        DocumentSnapshot? openingDoc;
        for (final hDoc in historyDocs) {
          final hData = hDoc.data() as Map<String, dynamic>;
          if (hData['type']?.toString() == 'opening') {
            openingDoc = hDoc;
            break;
          }
        }
        if (openingDoc != null) {
          final hData = openingDoc.data() as Map<String, dynamic>;
          if (hData['voucherId'] == null || hData['direction'] == null) {
            batch.update(openingDoc.reference, {
              'voucherId': voucherId,
              'direction': direction,
            });
            opCount++;
            await commitBatchIfNeeded();
          }
        } else {
          final newDocRef = supplierRef.collection('balanceHistory').doc();
          batch.set(newDocRef, {
            'enteredBalance': amount,
            'balanceBefore': 0.0,
            'timestamp': timestamp,
            'type': 'opening',
            'voucherId': voucherId,
            'direction': direction,
            'notes': 'رصيد افتتاحي',
          });
          opCount++;
          await commitBatchIfNeeded();
        }
      } else {
        if (historyVoucherDocs.containsKey(voucherId)) {
          final hDoc = historyVoucherDocs[voucherId]!;
          final hData = hDoc.data() as Map<String, dynamic>;
          final hAmount = invoiceNum(hData['enteredBalance']);
          final hDirection = hData['direction']?.toString();
          if ((hAmount - amount).abs() > 0.001 || hDirection != direction) {
            batch.update(hDoc.reference, {
              'enteredBalance': amount,
              'direction': direction,
              'notes': noteStr.isNotEmpty
                  ? noteStr
                  : 'سند $direction رقم $voucherNumber',
            });
            opCount++;
            await commitBatchIfNeeded();
          }
        } else {
          // Look if there is an existing voucher doc without voucherId
          DocumentSnapshot? matchedDoc;
          for (final hDoc in historyDocs) {
            final hData = hDoc.data() as Map<String, dynamic>;
            if (hData['type']?.toString() == 'voucher' &&
                hData['voucherId'] == null) {
              final notes = hData['notes']?.toString() ?? '';
              if (notes.contains('رقم $voucherNumber') ||
                  (invoiceNum(hData['enteredBalance']) - amount).abs() <
                      0.001) {
                matchedDoc = hDoc;
                break;
              }
            }
          }

          if (matchedDoc != null) {
            batch.update(matchedDoc.reference, {
              'voucherId': voucherId,
              'direction': direction,
              'enteredBalance': amount,
            });
            opCount++;
            await commitBatchIfNeeded();
          } else {
            final newDocRef = supplierRef.collection('balanceHistory').doc();
            batch.set(newDocRef, {
              'enteredBalance': amount,
              'balanceBefore': 0.0,
              'timestamp': timestamp,
              'type': 'voucher',
              'voucherId': voucherId,
              'direction': direction,
              'notes': noteStr.isNotEmpty
                  ? noteStr
                  : 'سند $direction رقم $voucherNumber',
            });
            opCount++;
            await commitBatchIfNeeded();
          }
        }
      }
    }

    // Delete redundant records
    for (final doc in historyDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString();
      final invId = data['invoiceId']?.toString() ?? '';
      final vId = data['voucherId']?.toString() ?? '';

      if (type == 'buying' || type == 'buying_payment') {
        if (!buyingMap.containsKey(invId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      } else if (type == 'voucher' || type == 'opening') {
        if (vId.isNotEmpty && !vouchersMap.containsKey(vId)) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    // Refresh history documents to get the final aligned state
    final finalHistoryDocs =
        (await supplierRef.collection('balanceHistory').get()).docs;
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
      final direction = data['direction']?.toString() ?? 'له';

      if ((currentBefore - running).abs() > 0.001) {
        recalculateBatch.update(doc.reference, {'balanceBefore': running});
        recCount++;
        if (recCount >= _maxBatchOps) {
          await recalculateBatch.commit();
          recalculateBatch = _firestore.batch();
          recCount = 0;
        }
      }

      if (invId.isNotEmpty) {
        if (type == 'buying') {
          invPreviousBalances[invId] = running;
        }
      }

      // Buying invoice: we owe more → increase running balance.
      // Buying payment: we paid → decrease running balance.
      // Voucher / opening 'له' (supplier lent / owed to us for goods): increase.
      // Voucher / opening 'عليه' (we pay the supplier): decrease.
      if (type == 'buying') {
        running += entered;
      } else if (type == 'buying_payment') {
        running -= entered;
      } else if (type == 'opening' || type == 'voucher') {
        if (direction == 'له') {
          running += entered;
        } else {
          running -= entered;
        }
      }

      if (invId.isNotEmpty) {
        invAfterBalances[invId] = running;
      }
    }

    if (recCount > 0) {
      await recalculateBatch.commit();
    }

    // Update supplier balance on main doc
    await supplierRef.set({'totalBalance': running}, SetOptions(merge: true));

    WriteBatch finalBatch = _firestore.batch();
    var finalOpCount = 0;

    for (final doc in buyingDocs) {
      final invoiceId = doc.id;
      final prevBal = invPreviousBalances[invoiceId] ?? 0.0;
      final afterBal = invAfterBalances[invoiceId] ?? 0.0;

      final data = doc.data() as Map<String, dynamic>;
      final storedPrev = invoiceNum(data['previousBalance']);
      final storedBal = invoiceNum(data['balance']);

      if ((storedPrev - prevBal).abs() > 0.001 ||
          (storedBal - afterBal).abs() > 0.001) {
        finalBatch.update(doc.reference, {
          'previousBalance': prevBal,
          'balance': afterBal,
        });
        finalOpCount++;
        if (finalOpCount >= _maxBatchOps) {
          await finalBatch.commit();
          finalBatch = _firestore.batch();
          finalOpCount = 0;
        }

        final rootId = data['invoiceId']?.toString() ?? doc.id;
        if (rootId.isNotEmpty) {
          final rootRef = _firestore.collection('buying invoices').doc(rootId);
          final rootSnap = await rootRef.get();
          if (rootSnap.exists) {
            finalBatch.update(rootRef, {
              'previousBalance': prevBal,
              'balance': afterBal,
            });
            finalOpCount++;
            if (finalOpCount >= _maxBatchOps) {
              await finalBatch.commit();
              finalBatch = _firestore.batch();
              finalOpCount = 0;
            }
          }
        }
      }
    }

    if (finalOpCount > 0) {
      await finalBatch.commit();
    }
  }
}
