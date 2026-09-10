import 'package:cloud_firestore/cloud_firestore.dart';
import '../sync/connectivity_service.dart';
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
      case 'buying_return':
      case 'return':
        return 3;
      case 'buying_return_payment':
      case 'return_payment':
        return 4;
      case 'voucher':
        return 5;
      default:
        return 6;
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
    if (!ConnectivityService.instance.isOnline) return;

    final trimmed = supplierId.trim();
    if (trimmed.isEmpty) return;

    final supplierRef = _firestore.collection('suppliers').doc(trimmed);
    final supplierSnap = await supplierRef.get();
    if (!supplierSnap.exists) return;
    final supplierData = supplierSnap.data() as Map<String, dynamic>? ?? {};
    final supplierName =
        (supplierData['name'] ?? supplierData['supplierName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final results = await Future.wait([
      supplierRef.collection('buying invoices').get(),
      supplierRef.collection('balanceHistory').get(),
      _firestore
          .collection('supplier_vouchers')
          .where('supplierId', isEqualTo: trimmed)
          .get(),
      _firestore.collection('buying invoices').get(),
      supplierRef.collection('returnBuyingInvoices').get(),
    ]);

    final subcollectionBuyingDocs = results[0].docs;
    final historyDocs = results[1].docs;
    final voucherDocs = results[2].docs;
    final rootBuyingDocs = results[3].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final rootSupplierId = data['supplierId']?.toString().trim() ?? '';
      if (rootSupplierId.isNotEmpty) return rootSupplierId == trimmed;
      final rootSupplierName =
          data['supplierName']?.toString().trim().toLowerCase() ?? '';
      return supplierName.isNotEmpty && rootSupplierName == supplierName;
    });
    final returnDocs = results[4].docs;

    String canonicalInvoiceId(QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final linkedId = data['invoiceId']?.toString().trim() ?? '';
      if (linkedId.isNotEmpty) return linkedId;
      final storedId = data['id']?.toString().trim() ?? '';
      return storedId.isNotEmpty ? storedId : doc.id;
    }

    final buyingByIdentity = <String, QueryDocumentSnapshot>{};
    for (final doc in [...subcollectionBuyingDocs, ...rootBuyingDocs]) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final invoiceNumber = data['invoiceNumber']?.toString().trim() ?? '';
      final canonicalId = canonicalInvoiceId(doc);
      final identity = invoiceNumber.isNotEmpty
          ? 'number:$invoiceNumber'
          : 'id:$canonicalId';
      buyingByIdentity.putIfAbsent(identity, () => doc);
    }
    final buyingDocs = buyingByIdentity.values.toList();

    String? resolveInvoiceId(String historyInvoiceId, String invoiceNumber) {
      for (final invoice in buyingDocs) {
        final data = invoice.data() as Map<String, dynamic>? ?? {};
        final canonicalId = canonicalInvoiceId(invoice);
        final linkedId = data['invoiceId']?.toString().trim() ?? '';
        final storedId = data['id']?.toString().trim() ?? '';
        final currentNumber = data['invoiceNumber']?.toString().trim() ?? '';
        if (historyInvoiceId.isNotEmpty &&
            (historyInvoiceId == canonicalId ||
                historyInvoiceId == invoice.id ||
                historyInvoiceId == linkedId ||
                historyInvoiceId == storedId)) {
          return canonicalId;
        }
        if (invoiceNumber.isNotEmpty &&
            currentNumber.isNotEmpty &&
            invoiceNumber == currentNumber) {
          return canonicalId;
        }
      }
      return null;
    }

    String? resolveReturnId(String historyInvoiceId, String invoiceNumber) {
      for (final invoice in returnDocs) {
        final data = invoice.data() as Map<String, dynamic>? ?? {};
        final canonicalId = canonicalInvoiceId(invoice);
        final currentNumber = data['invoiceNumber']?.toString().trim() ?? '';
        if (historyInvoiceId.isNotEmpty &&
            (historyInvoiceId == canonicalId ||
                historyInvoiceId == invoice.id)) {
          return canonicalId;
        }
        if (invoiceNumber.isNotEmpty &&
            currentNumber.isNotEmpty &&
            invoiceNumber == currentNumber) {
          return canonicalId;
        }
      }
      return null;
    }

    List<QueryDocumentSnapshot> sortAndDeduplicateHistory(
      List<QueryDocumentSnapshot> docs,
    ) {
      final sorted = _sortDocsAscending(docs);
      final seen = <String>{};
      return sorted.where((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final type = data['type']?.toString() ?? '';
        final isBuying = type == 'buying' || type == 'buying_payment';
        final isReturn = type == 'buying_return' ||
            type == 'return' ||
            type == 'buying_return_payment' ||
            type == 'return_payment';
        if (!isBuying && !isReturn) return true;
        final invId = data['invoiceId']?.toString().trim() ?? '';
        final invNum = data['invoiceNumber']?.toString().trim() ?? '';
        final resolvedId = isReturn
            ? resolveReturnId(invId, invNum)
            : resolveInvoiceId(invId, invNum);
        final identity = resolvedId ??
            (invNum.isNotEmpty
                ? 'number:$invNum'
                : (invId.isNotEmpty ? 'id:$invId' : 'doc:${doc.id}'));
        final canonicalType = type == 'return'
            ? 'buying_return'
            : type == 'return_payment'
                ? 'buying_return_payment'
                : type;
        return seen.add('$identity:$canonicalType');
      }).toList();
    }

    final Map<String, DocumentSnapshot> vouchersMap = {
      for (var doc in voucherDocs) doc.id: doc
    };

    final Map<String, QueryDocumentSnapshot> historyBuyingDocs = {};
    final Map<String, QueryDocumentSnapshot> historyBuyingPaymentDocs = {};
    final Map<String, QueryDocumentSnapshot> historyVoucherDocs = {};
    final Map<String, QueryDocumentSnapshot> historyReturnDocs = {};
    final Map<String, QueryDocumentSnapshot> historyReturnPaymentDocs = {};

    for (final doc in historyDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString();
      final invId = data['invoiceId']?.toString() ?? '';
      final invNum = data['invoiceNumber']?.toString() ?? '';
      final vId = data['voucherId']?.toString() ?? '';

      if (type == 'buying') {
        final resolvedId = resolveInvoiceId(invId, invNum);
        if (resolvedId == null) {
          // Will delete later in clean phase
        } else {
          historyBuyingDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'buying_payment') {
        final resolvedId = resolveInvoiceId(invId, invNum);
        if (resolvedId == null) {
          // Will delete later
        } else {
          historyBuyingPaymentDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'voucher' || type == 'opening') {
        if (vId.isNotEmpty && vouchersMap.containsKey(vId)) {
          historyVoucherDocs.putIfAbsent(vId, () => doc);
        }
      } else if (type == 'buying_return' || type == 'return') {
        final resolvedId = resolveReturnId(invId, invNum);
        if (resolvedId != null) {
          historyReturnDocs.putIfAbsent(resolvedId, () => doc);
        }
      } else if (type == 'buying_return_payment' || type == 'return_payment') {
        final resolvedId = resolveReturnId(invId, invNum);
        if (resolvedId != null) {
          historyReturnPaymentDocs.putIfAbsent(resolvedId, () => doc);
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
      final invoiceId = canonicalInvoiceId(doc);
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
        final newDocRef =
            supplierRef.collection('balanceHistory').doc('${invoiceId}_buying');
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
          final newDocRef =
              supplierRef.collection('balanceHistory').doc('${invoiceId}_pay');
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

    // Align purchase-return records. A return reduces what is owed, while any
    // cash refund recorded on it increases the running balance again.
    for (final doc in returnDocs) {
      final invoiceId = canonicalInvoiceId(doc);
      final data = doc.data() as Map<String, dynamic>;
      final totalSum = invoiceNum(data['totalSum']);
      final paidAmount = invoiceNum(data['paidAmount']);
      final invoiceNumber = data['invoiceNumber']?.toString() ?? '';
      final timestamp = data['date'] ?? FieldValue.serverTimestamp();

      final returnHistory = historyReturnDocs[invoiceId];
      if (returnHistory == null) {
        final ref = supplierRef
            .collection('balanceHistory')
            .doc('${invoiceId}_buying_return');
        batch.set(ref, {
          'enteredBalance': totalSum,
          'balanceBefore': 0.0,
          'timestamp': timestamp,
          'type': 'buying_return',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
        opCount++;
        await commitBatchIfNeeded();
      } else if ((invoiceNum((returnHistory.data()
                      as Map<String, dynamic>)['enteredBalance']) -
                  totalSum)
              .abs() >
          0.001) {
        batch.update(returnHistory.reference, {'enteredBalance': totalSum});
        opCount++;
        await commitBatchIfNeeded();
      }

      final paymentHistory = historyReturnPaymentDocs[invoiceId];
      if (paidAmount > 0 && paymentHistory == null) {
        final ref = supplierRef
            .collection('balanceHistory')
            .doc('${invoiceId}_buying_return_pay');
        batch.set(ref, {
          'enteredBalance': paidAmount,
          'balanceBefore': 0.0,
          'timestamp': timestamp,
          'type': 'buying_return_payment',
          'invoiceId': invoiceId,
          'invoiceNumber': invoiceNumber,
        });
        opCount++;
        await commitBatchIfNeeded();
      } else if (paidAmount > 0 && paymentHistory != null) {
        final current = invoiceNum(
            (paymentHistory.data() as Map<String, dynamic>)['enteredBalance']);
        if ((current - paidAmount).abs() > 0.001) {
          batch.update(paymentHistory.reference, {
            'enteredBalance': paidAmount,
          });
          opCount++;
          await commitBatchIfNeeded();
        }
      } else if (paidAmount <= 0 && paymentHistory != null) {
        batch.delete(paymentHistory.reference);
        opCount++;
        await commitBatchIfNeeded();
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
      final invNum = data['invoiceNumber']?.toString() ?? '';
      final vId = data['voucherId']?.toString() ?? '';

      if (type == 'buying' || type == 'buying_payment') {
        if (resolveInvoiceId(invId, invNum) == null) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      } else if (type == 'buying_return' || type == 'return') {
        if (resolveReturnId(invId, invNum) == null) {
          batch.delete(doc.reference);
          opCount++;
          await commitBatchIfNeeded();
        }
      } else if (type == 'buying_return_payment' || type == 'return_payment') {
        if (resolveReturnId(invId, invNum) == null) {
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
    final sorted = sortAndDeduplicateHistory(finalHistoryDocs);

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
      final rawInvId = data['invoiceId']?.toString() ?? '';
      final invNum = data['invoiceNumber']?.toString() ?? '';
      final invId = resolveInvoiceId(rawInvId, invNum) ?? rawInvId;
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
      if (type == 'buying' || type == 'addition') {
        running += entered;
      } else if (type == 'buying_payment') {
        running -= entered;
      } else if (type == 'buying_return' || type == 'return') {
        running -= entered;
      } else if (type == 'buying_return_payment' || type == 'return_payment') {
        running += entered;
      } else if (type == 'opening' || type == 'voucher') {
        final isIncrease = type == 'opening'
            ? direction != '\u0639\u0644\u064a\u0647'
            : direction == '\u0644\u0647';
        if (isIncrease) {
          running += entered;
        } else {
          running -= entered;
        }
      } else if (type == 'deduction') {
        running -= entered;
      }

      if (invId.isNotEmpty) {
        invAfterBalances[invId] = running;
      }
    }

    if (recCount > 0) {
      await recalculateBatch.commit();
    }

    // Update supplier balance on main doc
    await supplierRef.set(
      {'totalBalance': running, 'balance': running},
      SetOptions(merge: true),
    );

    WriteBatch finalBatch = _firestore.batch();
    var finalOpCount = 0;

    for (final doc in buyingDocs) {
      final invoiceId = canonicalInvoiceId(doc);
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
