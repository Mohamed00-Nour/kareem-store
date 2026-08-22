import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/box_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../sync/connectivity_service.dart';
import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';
import 'invoice_stock_service.dart';
import 'sales_invoice_actions_service.dart';

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
    final newBalance = totalSumFinal - paidAmount;
    final newRemaining = newBalance;
    final previousBalance = invoiceNum(originalInvoice['previousBalance']);

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
      'balance': newBalance,
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
      await ClientRepository.instance.updateLocalBalance(newClientId, updatedBal);
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
        'invoiceId': rootInvoiceId,
        'updateData': rootUpdate,
        'oldProducts': oldProducts,
        'newProducts': newProducts,
      },
    );

    // 5. If online, also execute direct Firestore write in background safely
    try {
      final rootRef =
          FirebaseFirestore.instance.collection(collection).doc(rootInvoiceId);
      await rootRef.update(rootUpdate);

      final clientSubFields = <String, dynamic>{
        'invoiceId': rootInvoiceId,
        'invoiceNumber': invoiceNumber,
        'clientId': newClientId,
        'date': selectedDate,
        'totalSum': totalSumFinal,
        'paidAmount': paidAmount,
        'balance': newBalance,
        'previousBalance': previousBalance,
        'paymentMethod': paymentMethod,
        'notes': notes,
        'invoiceDiscount': effectiveDiscountAmt,
        'products': newProducts,
      };

      DocumentReference<Map<String, dynamic>>? oldSubRef;
      if (clientSubInvoiceDocId != null &&
          clientSubInvoiceDocId.isNotEmpty &&
          oldClientId != null) {
        oldSubRef = FirebaseFirestore.instance
            .collection('clients')
            .doc(oldClientId)
            .collection('invoices')
            .doc(clientSubInvoiceDocId);
      } else if (oldClientId != null) {
        final found = await SalesInvoiceActionsService.findClientSubInvoice(
          clientId: oldClientId,
          rootInvoiceId: rootInvoiceId,
        );
        if (found != null) {
          oldSubRef = found.reference;
        }
      }

      if (oldClient == clientName) {
        if (oldSubRef != null) {
          final subSnap = await oldSubRef.get();
          if (subSnap.exists) {
            await oldSubRef.update(clientSubFields);
          } else {
            await FirebaseFirestore.instance
                .collection('clients')
                .doc(newClientId)
                .collection('invoices')
                .add(clientSubFields);
          }
        } else {
          await FirebaseFirestore.instance
              .collection('clients')
              .doc(newClientId)
              .collection('invoices')
              .add(clientSubFields);
        }
      } else {
        if (oldSubRef != null && (await oldSubRef.get()).exists) {
          await oldSubRef.delete();
        }
        await FirebaseFirestore.instance
            .collection('clients')
            .doc(newClientId)
            .collection('invoices')
            .add(clientSubFields);
      }

      if (oldClientId != null) {
        final oldClientRef =
            FirebaseFirestore.instance.collection('clients').doc(oldClientId);
        final oldSnap = await oldClientRef.get();
        if (oldSnap.exists) {
          final current = invoiceNum(oldSnap.data()?['balance']);
          if (oldClient == clientName) {
            await oldClientRef.update({
              'balance': current - oldRemaining + newRemaining,
            });
          } else {
            await oldClientRef.update({'balance': current - oldRemaining});
          }
        }
      }

      if (newClientId != null && oldClient != clientName) {
        final newClientRef =
            FirebaseFirestore.instance.collection('clients').doc(newClientId);
        final newSnap = await newClientRef.get();
        final newCurrent =
            newSnap.exists ? invoiceNum(newSnap.data()?['balance']) : 0.0;
        await newClientRef.set({
          'clientName': clientName,
          'balance': newCurrent + newRemaining,
          'id': newClientId,
        }, SetOptions(merge: true));
      }

      if (paidDelta.abs() > 0.001) {
        final boxDocRef =
            FirebaseFirestore.instance.collection('box').doc('mainBox');
        await boxDocRef.set(
          {'value': FieldValue.increment(paidDelta)},
          SetOptions(merge: true),
        );
        await boxDocRef.collection('changes').add({
          'date': FieldValue.serverTimestamp(),
          'value': paidDelta,
          'type': paidDelta >= 0 ? 'addition' : 'subtraction',
          'name': clientName,
          'invoiceNumber': invoiceNumber,
        });
      }
    } catch (_) {
      // Offline / network failure - already queued for sync
    }

    ConnectivityService.instance.forceSync();
  }
}
