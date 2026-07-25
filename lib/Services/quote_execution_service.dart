import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_invoice_balance_sync_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';

/// Converts a saved price-quote document into a real sales invoice.
///
/// On success:
///   - Writes to `invoices` collection.
///   - Updates stock quantities.
///   - Updates client balance + subcollection + balanceHistory.
///   - Updates `box/mainBox`.
///   - **Deletes** the quote document from `price_quotes`.
///
/// Returns the saved invoice map (same shape as a normal invoice).
class QuoteExecutionService {
  QuoteExecutionService._();

  static final _db = FirebaseFirestore.instance;

  /// Execute [quoteId] / [quoteData] as a real sales invoice.
  ///
  /// [previousClientBalance] should be fetched fresh just before calling.
  static Future<Map<String, dynamic>> executeQuote({
    required String quoteId,
    required Map<String, dynamic> quoteData,
    required double previousClientBalance,
  }) async {
    final clientName = quoteData['clientName']?.toString() ?? '';
    final lines = List<Map<String, dynamic>>.from(
        (quoteData['products'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    final totalSumBeforeDiscount =
        lines.fold<double>(0.0, (acc, p) => acc + invoiceNum(p['total']));

    final invoiceDiscount = invoiceNum(quoteData['invoiceDiscount']);
    final discountIsPercent =
        (quoteData['discountIsPercent'] as bool?) ?? false;

    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;

    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;
    final paidAmount = invoiceNum(quoteData['paidAmount']);
    final paymentMethod = quoteData['paymentMethod']?.toString() ?? 'نقداً';
    final notes = quoteData['notes']?.toString() ?? '';

    final date = () {
      final d = quoteData['date'];
      if (d is Timestamp) return d.toDate();
      if (d is DateTime) return d;
      return DateTime.now();
    }();

    // ── Resolve client id ──────────────────────────────────────────────────
    String? clientId = quoteData['clientId']?.toString();
    if (clientId == null || clientId.isEmpty) {
      final q = await _db
          .collection('clients')
          .where('clientName', isEqualTo: clientName)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        clientId = q.docs.first.id;
      } else {
        final ref = _db.collection('clients').doc();
        clientId = ref.id;
        await ref.set({
          'clientName': clientName,
          'balance': 0.0,
          'id': clientId,
        });
      }
    }

    // ── Fetch next invoice number ──────────────────────────────────────────
    final invQ = await _db
        .collection('invoices')
        .orderBy('invoiceNumber', descending: true)
        .limit(1)
        .get();
    final newInvoiceNumber = invQ.docs.isEmpty
        ? 1
        : (invQ.docs.first['invoiceNumber'] as num).toInt() + 1;

    // ── Resolve product catalog ────────────────────────────────────────────
    final catalog = await InvoiceStockService.resolveCatalogIfNeeded(
      lines: lines,
      seed: const {},
    );

    final totalCost = InvoiceStockService.computeCostTotal(lines, catalog);
    final profitMargin = totalSumFinal - totalCost;
    final balance = totalSumFinal - paidAmount;
    final updatedBalance = previousClientBalance + balance;

    // ── Build invoice document ─────────────────────────────────────────────
    final docRef = _db.collection('invoices').doc();
    final invoiceData = <String, dynamic>{
      'id': docRef.id,
      'invoiceNumber': newInvoiceNumber,
      'clientName': clientName,
      'clientId': clientId,
      'date': date,
      'totalSum': totalSumFinal,
      'profitMargin': profitMargin,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousClientBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': effectiveDiscountAmt,
      'invoiceType': 'sale',
      'isSpecial': false,
      'products': lines,
    };

    final clientDocRef = _db.collection('clients').doc(clientId);
    final boxDocRef = _db.collection('box').doc('mainBox');

    // ── Parallel writes ────────────────────────────────────────────────────
    await Future.wait([
      docRef.set(invoiceData),
      InvoiceStockService.applyStockChanges(
        lines: lines,
        restore: false,
        changeDate: date,
        catalog: catalog,
      ),
      _commitClientAndBox(
        clientDocRef: clientDocRef,
        boxDocRef: boxDocRef,
        clientName: clientName,
        updatedBalance: updatedBalance,
        invoiceId: docRef.id,
        newInvoiceNumber: newInvoiceNumber,
        totalSumFinal: totalSumFinal,
        paidAmount: paidAmount,
        balance: balance,
        previousClientBalance: previousClientBalance,
        paymentMethod: paymentMethod,
        notes: notes,
        products: lines,
        invoiceDiscount: effectiveDiscountAmt,
        date: date,
      ),
    ]);

    // ── Sync client balance ────────────────────────────────────────────────
    await ClientInvoiceBalanceSyncService.syncForClient(clientId);

    // ── Delete the quote ───────────────────────────────────────────────────
    await _db.collection('price_quotes').doc(quoteId).delete();

    return invoiceData;
  }

  static Future<void> _commitClientAndBox({
    required DocumentReference<Map<String, dynamic>> clientDocRef,
    required DocumentReference<Map<String, dynamic>> boxDocRef,
    required String clientName,
    required double updatedBalance,
    required String invoiceId,
    required int newInvoiceNumber,
    required double totalSumFinal,
    required double paidAmount,
    required double balance,
    required double previousClientBalance,
    required String paymentMethod,
    required String notes,
    required List<Map<String, dynamic>> products,
    required double invoiceDiscount,
    required DateTime date,
  }) async {
    final batch = _db.batch();

    batch.set(
      clientDocRef,
      {'clientName': clientName, 'balance': updatedBalance},
      SetOptions(merge: true),
    );

    batch.set(clientDocRef.collection('invoices').doc(), {
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
      'date': date,
      'totalSum': totalSumFinal,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousClientBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': invoiceDiscount,
      'isSpecial': false,
      'products': products,
    });

    // balanceHistory: sale entry (debt increase)
    batch.set(clientDocRef.collection('balanceHistory').doc(), {
      'enteredBalance': totalSumFinal,
      'balanceBefore': previousClientBalance,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'sale',
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
    });

    // balanceHistory: payment entry (debt decrease)
    if (paidAmount > 0) {
      batch.set(clientDocRef.collection('balanceHistory').doc(), {
        'enteredBalance': paidAmount,
        'balanceBefore': previousClientBalance + totalSumFinal,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'sale_payment',
        'invoiceId': invoiceId,
        'invoiceNumber': newInvoiceNumber,
      });
    }

    // box
    batch.set(
      boxDocRef,
      {'value': FieldValue.increment(paidAmount)},
      SetOptions(merge: true),
    );
    batch.set(boxDocRef.collection('changes').doc(), {
      'date': FieldValue.serverTimestamp(),
      'value': paidAmount,
      'type': 'addition',
      'name': clientName,
      'invoiceNumber': newInvoiceNumber,
    });

    await batch.commit();
  }
}

