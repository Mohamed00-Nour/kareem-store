import 'package:uuid/uuid.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';

/// Persists a return invoice: restores stock, updates client & box locally first,
/// then pushes to Firestore in the background.
class ReturnInvoiceSaveService {
  static const _uuid = Uuid();

  static Future<Map<String, dynamic>> save({
    required String clientName,
    required DateTime? selectedDate,
    required List<Map<String, dynamic>> products,
    required double paidAmount,
    required String paymentMethod,
    required String notes,
    required double invoiceDiscount,
    required bool discountIsPercent,
    required double previousBalanceSnapshot,
    required double totalSumBeforeDiscount,
    required Future<double> Function(List<Map<String, dynamic>> products)
        calculateTotalCost,
    Map<String, ResolvedInvoiceProduct> productCatalog = const {},
  }) async {
    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;

    // 1. Resolve client locally from Hive
    var client = ClientRepository.instance.findByName(clientName);
    String clientId;
    double existingBalance = 0.0;

    if (client != null) {
      clientId = client.id;
      existingBalance = client.balance;
    } else {
      clientId = _uuid.v4();
      await ClientRepository.instance.upsertLocal(clientId, {
        'clientName': clientName,
        'balance': 0.0,
        'id': clientId,
      });
      // Also enqueue creation of new client if created here
      await SyncQueueManager.instance.enqueue(
        operationType: 'createClient',
        payload: {
          'clientId': clientId,
          'data': {'clientName': clientName, 'balance': 0.0},
          'openingBalance': 0.0,
        },
      );
    }

    // 2. Resolve catalog & next invoice number locally (instant)
    final catalog = await InvoiceStockService.resolveCatalogIfNeeded(
      lines: products,
      seed: productCatalog,
    );
    final totalCost = InvoiceStockService.computeCostTotal(products, catalog);
    final newInvoiceNumber = LocalInvoiceCounter.nextNumber('return');

    final profitMargin = -(totalSumFinal - totalCost);
    final balance = totalSumFinal - paidAmount;
    final updatedBalance = existingBalance - balance;
    final invoiceDocId = _uuid.v4();
    final date = selectedDate ?? DateTime.now();

    final invoiceData = <String, dynamic>{
      'id': invoiceDocId,
      'invoiceId': invoiceDocId,
      'invoiceNumber': newInvoiceNumber,
      'clientName': clientName,
      'clientId': clientId,
      'date': date,
      'totalSum': totalSumFinal,
      'profitMargin': profitMargin,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalanceSnapshot,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': effectiveDiscountAmt,
      'invoiceType': 'return',
      'isSpecial': false,
      'products': products,
    };

    // 3. Immediately persist in Hive (Primary DB)
    await InvoiceRepository.instance.upsertReturnLocal(invoiceDocId, invoiceData);
    await ClientRepository.instance.updateLocalBalance(clientId, updatedBalance);
    if (paidAmount > 0) {
      await BoxRepository.instance.decrement(paidAmount);
    }
    await InvoiceStockService.applyStockChanges(
      lines: products,
      restore: true,
      changeDate: date,
      changeTypeWhenRestore: 'return',
      catalog: catalog,
    );

    // Save balance history entries locally
    final hist1Id = _uuid.v4();
    await BalanceHistoryRepository.instance.upsertLocal(
      BalanceHistoryLocal(
        id: hist1Id,
        parentId: clientId,
        parentType: 'client',
        enteredBalance: totalSumFinal,
        balanceBefore: existingBalance,
        type: 'return',
        invoiceId: invoiceDocId,
        invoiceNumber: newInvoiceNumber.toString(),
        timestamp: date,
      ),
    );

    if (paidAmount > 0) {
      final hist2Id = _uuid.v4();
      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: hist2Id,
          parentId: clientId,
          parentType: 'client',
          enteredBalance: paidAmount,
          balanceBefore: existingBalance - totalSumFinal,
          type: 'return_payment',
          invoiceId: invoiceDocId,
          invoiceNumber: newInvoiceNumber.toString(),
          timestamp: date,
        ),
      );
    }

    // 4. Enqueue background push to Firestore
    await SyncQueueManager.instance.enqueue(
      operationType: 'createReturn',
      payload: {
        'clientId': clientId,
        'invoiceId': invoiceDocId,
        'invoiceData': invoiceData,
        'products': products,
        'totalSum': totalSumFinal,
        'paidAmount': paidAmount,
      },
    );

    // Trigger sync in background (fire-and-forget, non-blocking)
    ConnectivityService.instance.forceSync();

    return invoiceData;
  }
}
