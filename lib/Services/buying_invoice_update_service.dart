import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'supplier_invoice_balance_sync_service.dart';

/// Updates an existing buying invoice locally in Hive first, then pushes to Firestore.
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

    // ── 1. Stock changes in Hive (Primary DB) ──
    await InvoiceStockService.applyStockChanges(
      lines: oldProducts,
      restore: false, // decrease: undo original purchase
      changeDate: selectedDate,
      changeTypeWhenDecrease: 'decrease',
    );

    await InvoiceStockService.applyStockChanges(
      lines: newProducts,
      restore: true, // increase: apply new purchase
      changeDate: selectedDate,
      changeTypeWhenRestore: 'increase',
    );

    // ── 2. Compute new totals ──
    final totalBeforeDiscount = newProducts.fold(
      0.0,
      (sum, p) => sum + (p['totalCost'] as num).toDouble(),
    );
    final totalSum = totalBeforeDiscount - invoiceDiscount;
    final balance = totalSum - paidAmount;

    final rootUpdate = <String, dynamic>{
      'id': rootInvoiceId,
      'invoiceId': rootInvoiceId,
      'invoiceNumber': invoiceNumber,
      'supplierName': supplierName,
      'supplierId': supplierId,
      'date': selectedDate ?? DateTime.now(),
      'totalSum': totalSum,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalance,
      'invoiceDiscount': invoiceDiscount,
      'notes': notes,
      'paymentMethod': balance == 0 ? 'نقد' : 'آجل',
      'invoiceType': 'buying',
      'products': newProducts
          .map((p) => {
                'product': p['product'],
                'amount': (p['amount'] as num).toDouble(),
                'cost': (p['cost'] as num).toDouble(),
                'totalCost': (p['totalCost'] as num).toDouble(),
              })
          .toList(),
    };

    // ── 3. Update Hive immediately ──
    await InvoiceRepository.instance.upsertBuyingLocal(rootInvoiceId, rootUpdate);

    final paidDelta = paidAmount - oldPaid;
    if (paidDelta.abs() > 0.001) {
      await BoxRepository.instance.decrement(paidDelta);
    }

    if (supplierId.isNotEmpty) {
      final localSup = SupplierRepository.instance.getById(supplierId);
      if (localSup != null) {
        final oldTotal = invoiceNum(originalInvoice['totalSum']);
        final oldBal = oldTotal - oldPaid;
        final newBal = balance;
        await SupplierRepository.instance.updateLocalBalance(
          supplierId,
          localSup.balance - oldBal + newBal,
        );
      }
    }

    // ── 4. Enqueue to SyncQueue ──
    await SyncQueueManager.instance.enqueue(
      operationType: 'createBuyingInvoice',
      payload: {
        'supplierId': supplierId,
        'supplierName': supplierName,
        'invoiceId': rootInvoiceId,
        'invoiceData': rootUpdate,
        'products': newProducts,
        'paidAmount': paidAmount,
      },
    );

    // ── 5. Direct Firestore update if online (fails silently if offline) ──
    try {
      final rootRef = _db.collection('buying invoices').doc(rootInvoiceId);
      await rootRef.update(rootUpdate);

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

        await SupplierInvoiceBalanceSyncService.syncForSupplier(supplierId);
      }

      if (paidDelta.abs() > 0.001) {
        final boxDocRef = _db.collection('box').doc('mainBox');
        await boxDocRef.set(
          {'value': FieldValue.increment(-paidDelta)},
          SetOptions(merge: true),
        );
        await boxDocRef.collection('changes').add({
          'date': FieldValue.serverTimestamp(),
          'value': paidDelta.abs(),
          'type': paidDelta > 0 ? 'decrement' : 'addition',
          'name': supplierName,
          'invoiceNumber': invoiceNumber,
        });
      }
    } catch (_) {}

    ConnectivityService.instance.forceSync();
  }
}
