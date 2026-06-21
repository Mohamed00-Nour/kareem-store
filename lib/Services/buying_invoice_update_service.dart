import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'supplier_invoice_balance_sync_service.dart';

/// Updates an existing buying invoice (stock, supplier balance, box, supplier copy).
class BuyingInvoiceUpdateService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> updateBuyingInvoice({
    required String rootInvoiceId,
    required Map<String, dynamic> originalInvoice,
    required List<Map<String, dynamic>> newProducts,
    required String supplierName,
    required String supplierId,
    required DateTime? selectedDate,
    required double paidAmount,
    required String notes,
    required double invoiceDiscount,
  }) async {
    final oldProducts = List<Map<String, dynamic>>.from(
      (originalInvoice['products'] as List?) ?? [],
    );
    final oldPaid = invoiceNum(originalInvoice['paidAmount']);
    final invoiceNumber = originalInvoice['invoiceNumber'];
    final previousBalance = invoiceNum(originalInvoice['previousBalance']);

    // ── 1. Reverse old stock (buying = increase, so restoring = decrease) ──
    // For buying invoices: original save did quantity += amount.
    // To reverse: we decrease by old amounts (restore=false = decrease).
    // Then we apply new amounts (restore=true = increase).
    await InvoiceStockService.applyStockChanges(
      lines: oldProducts,
      restore: false, // decrease: undo the original purchase increase
      changeDate: selectedDate,
      changeTypeWhenDecrease: 'decrease',
    );

    // ── 2. Apply new stock (increase) ──
    await InvoiceStockService.applyStockChanges(
      lines: newProducts,
      restore: true, // increase: apply the new purchase
      changeDate: selectedDate,
      changeTypeWhenRestore: 'increase',
    );

    // ── 3. Compute new totals ──
    final totalBeforeDiscount = newProducts.fold(
      0.0,
      (sum, p) => sum + (p['totalCost'] as num).toDouble(),
    );
    final totalSum = totalBeforeDiscount - invoiceDiscount;
    final balance = totalSum - paidAmount;

    // ── 4. Update root buying invoice document ──
    final rootUpdate = <String, dynamic>{
      'supplierName': supplierName,
      'date': selectedDate,
      'totalSum': totalSum,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalance,
      'invoiceDiscount': invoiceDiscount,
      'notes': notes,
      'paymentMethod': balance == 0 ? 'نقد' : 'آجل',
      'products': newProducts
          .map((p) => {
                'product': p['product'],
                'amount': (p['amount'] as num).toDouble(),
                'cost': (p['cost'] as num).toDouble(),
                'totalCost': (p['totalCost'] as num).toDouble(),
              })
          .toList(),
    };

    final rootRef = _db.collection('buying invoices').doc(rootInvoiceId);
    final rootSnap = await rootRef.get();
    if (!rootSnap.exists) {
      throw StateError('الفاتورة غير موجودة في قاعدة البيانات');
    }
    await rootRef.update(rootUpdate);

    // ── 5. Update supplier sub-collection document ──
    if (supplierId.isNotEmpty) {
      final supplierRef = _db.collection('suppliers').doc(supplierId);
      final subQuery = await supplierRef
          .collection('buying invoices')
          .where('invoiceId', isEqualTo: rootInvoiceId)
          .limit(1)
          .get();

      final subUpdate = <String, dynamic>{
        ...rootUpdate,
        'invoiceId': rootInvoiceId,
        'invoiceNumber': invoiceNumber,
      };

      if (subQuery.docs.isNotEmpty) {
        await subQuery.docs.first.reference.update(subUpdate);
      } else {
        await supplierRef.collection('buying invoices').add(subUpdate);
      }

      // ── 6. Sync supplier balance ──
      await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
    }

    // ── 7. Adjust box value for paid-amount delta ──
    final paidDelta = paidAmount - oldPaid;
    if (paidDelta.abs() > 0.001) {
      final boxDocRef = _db.collection('box').doc('mainBox');
      await _db.runTransaction((transaction) async {
        final boxSnap = await transaction.get(boxDocRef);
        final currentValue = boxSnap.exists
            ? invoiceNum(boxSnap.data()?['value'])
            : 0.0;
        transaction.set(
          boxDocRef,
          {'value': currentValue - paidDelta},
          SetOptions(merge: true),
        );
      });
      await boxDocRef.collection('changes').add({
        'date': FieldValue.serverTimestamp(),
        'value': paidDelta.abs(),
        'type': paidDelta > 0 ? 'decrement' : 'addition',
        'name': supplierName,
        'invoiceNumber': invoiceNumber,
      });
    }
  }
}
