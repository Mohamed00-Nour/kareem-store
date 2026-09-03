import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';

/// Updates an existing buying invoice locally in Hive first, then pushes to Firestore.
class BuyingInvoiceUpdateService {
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
          .map((p) => Map<String, dynamic>.from(p))
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
    final syncOperationId =
        FirebaseFirestore.instance.collection('_sync_operations').doc().id;
    await SyncQueueManager.instance.enqueue(
      operationType: 'editBuyingInvoice',
      payload: {
        'supplierId': supplierId,
        'supplierName': supplierName,
        'invoiceId': rootInvoiceId,
        'invoiceData': rootUpdate,
        'oldProducts': oldProducts,
        'products': newProducts,
        'oldPaidAmount': oldPaid,
        'paidAmount': paidAmount,
        'syncOperationId': syncOperationId,
      },
    );

    ConnectivityService.instance.forceSync();
  }
}
