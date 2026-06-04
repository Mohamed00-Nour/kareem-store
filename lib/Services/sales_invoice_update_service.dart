import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';
import 'invoice_stock_service.dart';
import 'sales_invoice_actions_service.dart';

/// Updates an existing sales invoice (stock, balances, box, client copy).
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
  }) async {
    final oldProducts = List<Map<String, dynamic>>.from(
      (originalInvoice['products'] as List?) ?? [],
    );
    final oldClient = originalInvoice['clientName']?.toString() ?? '';
    final oldTotalSum = invoiceNum(originalInvoice['totalSum']);
    final oldPaid = invoiceNum(originalInvoice['paidAmount']);
    final oldRemaining = oldTotalSum - oldPaid;
    final invoiceNumber = originalInvoice['invoiceNumber'];

    final allLines = [...oldProducts, ...newProducts];
    final catalog = await InvoiceStockService.resolveCatalog(lines: allLines);

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
      'clientName': clientName,
      'date': selectedDate,
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

    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(rootInvoiceId)
        .update(rootUpdate);

    final clientSubFields = <String, dynamic>{
      'invoiceId': rootInvoiceId,
      'invoiceNumber': invoiceNumber,
      'date': selectedDate,
      'totalSum': totalSumFinal,
      'paidAmount': paidAmount,
      'balance': newBalance,
      'previousBalance': previousBalance,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'products': newProducts,
    };

    DocumentReference<Map<String, dynamic>>? oldSubRef;
    if (clientSubInvoiceDocId != null &&
        clientSubInvoiceDocId.isNotEmpty &&
        oldClient.isNotEmpty) {
      oldSubRef = FirebaseFirestore.instance
          .collection('clients')
          .doc(oldClient)
          .collection('invoices')
          .doc(clientSubInvoiceDocId);
    } else if (oldClient.isNotEmpty) {
      final found = await SalesInvoiceActionsService.findClientSubInvoice(
        clientId: oldClient,
        rootInvoiceId: rootInvoiceId,
      );
      if (found != null) {
        oldSubRef = found.reference;
      }
    }

    if (oldClient == clientName) {
      if (oldSubRef != null) {
        await oldSubRef.update(clientSubFields);
      } else {
        await FirebaseFirestore.instance
            .collection('clients')
            .doc(clientName)
            .collection('invoices')
            .add(clientSubFields);
      }
    } else {
      if (oldSubRef != null) {
        await oldSubRef.delete();
      }
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientName)
          .collection('invoices')
          .add(clientSubFields);
    }

    if (oldClient.isNotEmpty) {
      final oldClientRef =
          FirebaseFirestore.instance.collection('clients').doc(oldClient);
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

    if (clientName.isNotEmpty && clientName != oldClient) {
      final newClientRef =
          FirebaseFirestore.instance.collection('clients').doc(clientName);
      final newSnap = await newClientRef.get();
      final newCurrent =
          newSnap.exists ? invoiceNum(newSnap.data()?['balance']) : 0.0;
      await newClientRef.set({
        'clientName': clientName,
        'balance': newCurrent + newRemaining,
      }, SetOptions(merge: true));
    } else if (clientName.isNotEmpty && oldClient.isEmpty) {
      final newClientRef =
          FirebaseFirestore.instance.collection('clients').doc(clientName);
      final newSnap = await newClientRef.get();
      final newCurrent =
          newSnap.exists ? invoiceNum(newSnap.data()?['balance']) : 0.0;
      await newClientRef.set({
        'clientName': clientName,
        'balance': newCurrent + newRemaining,
      }, SetOptions(merge: true));
    }

    final paidDelta = paidAmount - oldPaid;
    if (paidDelta.abs() > 0.001) {
      final boxDocRef =
          FirebaseFirestore.instance.collection('box').doc('mainBox');
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final boxSnapshot = await transaction.get(boxDocRef);
        final currentBoxValue = boxSnapshot.exists
            ? invoiceNum(boxSnapshot.data()?['value'])
            : 0.0;
        transaction.set(
          boxDocRef,
          {'value': currentBoxValue + paidDelta},
          SetOptions(merge: true),
        );
      });
      await boxDocRef.collection('changes').add({
        'date': FieldValue.serverTimestamp(),
        'value': paidDelta,
        'type': paidDelta >= 0 ? 'addition' : 'subtraction',
        'name': clientName,
        'invoiceNumber': invoiceNumber,
      });
    }
  }
}
