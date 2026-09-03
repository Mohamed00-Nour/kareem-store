import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';
import 'invoice_stock_service.dart';

/// Updates an existing sales invoice locally in Hive first, then syncs to Firestore in background.
class SalesInvoiceUpdateService {
  static Future<double> productCostTotal(
      List<Map<String, dynamic>> products) async {
    return InvoiceStockService.computeCostTotalAsync(products);
  }

  static Future<void> updateSalesInvoice({
    required String rootInvoiceId,
    String? clientSubInvoiceDocId,
    required Map<String, dynamic> originalInvoice,
    required List<Map<String, dynamic>> newProducts,
    required String clientName,
    required DateTime? selectedDate,
    required double paidAmount,
    required String paymentMethod,
    required String notes,
    required double invoiceDiscount,
    required bool discountIsPercent,
    required double totalSumBeforeDiscount,
    String? sourceCollection,
  }) async {
    final collection = sourceCollection ??
        InvoiceSpecialService.sourceCollection(originalInvoice);
    final oldProducts = List<Map<String, dynamic>>.from(
      (originalInvoice['products'] as List?) ?? [],
    );
    final oldClient = originalInvoice['clientName']?.toString() ?? '';
    final oldTotalSum = invoiceNum(originalInvoice['totalSum']);
    final oldPaid = invoiceNum(originalInvoice['paidAmount']);
    final oldRemaining = oldTotalSum - oldPaid;
    final invoiceNumber = originalInvoice['invoiceNumber'];

    // 1. Resolve client locally from Hive
    String? newClientId;
    final localNewClient = ClientRepository.instance.findByName(clientName);
    if (localNewClient != null) {
      newClientId = localNewClient.id;
    } else {
      newClientId = originalInvoice['clientId']?.toString() ?? rootInvoiceId;
    }

    String? oldClientId;
    final localOldClient = ClientRepository.instance.findByName(oldClient);
    if (localOldClient != null) {
      oldClientId = localOldClient.id;
    } else {
      oldClientId = originalInvoice['clientId']?.toString();
    }

    final allLines = [...oldProducts, ...newProducts];
    final catalog =
        await InvoiceStockService.resolveCatalogIfNeeded(lines: allLines);

    // 2. Stock updates in Hive (Primary DB)
    await InvoiceStockService.applyStockChanges(
      lines: oldProducts,
      restore: true,
      changeDate: selectedDate,
      catalog: catalog,
    );
    await InvoiceStockService.applyStockChanges(
      lines: newProducts,
      restore: false,
      changeDate: selectedDate,
      catalog: catalog,
    );

    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;
    final totalCost =
        InvoiceStockService.computeCostTotal(newProducts, catalog);
    final profitMargin = totalSumFinal - totalCost;
    final previousBalance = invoiceNum(originalInvoice['previousBalance']);
    final newRemaining = totalSumFinal - paidAmount;
    final runningBalanceAfterInvoice = previousBalance + newRemaining;
    final syncOperationId =
        'sales_edit_${rootInvoiceId}_${DateTime.now().microsecondsSinceEpoch}';

    final rootUpdate = <String, dynamic>{
      'id': rootInvoiceId,
      'invoiceId': rootInvoiceId,
      'invoiceNumber': invoiceNumber,
      'clientName': clientName,
      'clientId': newClientId,
      'date': selectedDate ?? DateTime.now(),
      'totalSum': totalSumFinal,
      'profitMargin': profitMargin,
      'paidAmount': paidAmount,
      'balance': runningBalanceAfterInvoice,
      'invoiceRemaining': newRemaining,
      'previousBalance': previousBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': effectiveDiscountAmt,
      'products': newProducts,
      if (originalInvoice.containsKey('isSpecial'))
        'isSpecial': originalInvoice['isSpecial'] == true,
    };

    // 3. Update Hive local caches immediately
    await InvoiceRepository.instance.upsertSaleLocal(rootInvoiceId, rootUpdate);

    if (oldClient == clientName && newClientId != null) {
      final currentBal = localNewClient?.balance ?? 0.0;
      final updatedBal = currentBal - oldRemaining + newRemaining;
      await ClientRepository.instance
          .updateLocalBalance(newClientId, updatedBal);
    } else {
      if (oldClientId != null && localOldClient != null) {
        await ClientRepository.instance.updateLocalBalance(
          oldClientId,
          localOldClient.balance - oldRemaining,
        );
      }
      if (newClientId != null) {
        final currentNewBal = localNewClient?.balance ?? 0.0;
        await ClientRepository.instance.updateLocalBalance(
          newClientId,
          currentNewBal + newRemaining,
        );
      }
    }

    final paidDelta = paidAmount - oldPaid;
    if (paidDelta.abs() > 0.001) {
      await BoxRepository.instance.increment(paidDelta);
    }

    // 4. Enqueue to SyncQueue for background sync
    await SyncQueueManager.instance.enqueue(
      operationType: 'editInvoice',
      payload: {
        'clientId': newClientId ?? '',
        'oldClientId': oldClientId ?? '',
        'clientSubInvoiceDocId': clientSubInvoiceDocId ?? '',
        'invoiceId': rootInvoiceId,
        'sourceCollection': collection,
        'updateData': rootUpdate,
        'oldProducts': oldProducts,
        'newProducts': newProducts,
        'oldPaidAmount': oldPaid,
        'paidAmount': paidAmount,
        'syncOperationId': syncOperationId,
      },
    );

    ConnectivityService.instance.forceSync();
  }
}
