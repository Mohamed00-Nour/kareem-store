import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_stock_service.dart';

/// Persists a return invoice: restores stock, reverses profit/sales effect, updates client & box.
class ReturnInvoiceSaveService {
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
    final totalCost = await calculateTotalCost(products);
    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;
    final profitMargin = -(totalSumFinal - totalCost);
    final balance = totalSumFinal - paidAmount;

    final invoiceQuery = await FirebaseFirestore.instance
        .collection('returnInvoices')
        .orderBy('invoiceNumber', descending: true)
        .limit(1)
        .get();

    var newInvoiceNumber = 1;
    if (invoiceQuery.docs.isNotEmpty) {
      newInvoiceNumber = (invoiceQuery.docs.first['invoiceNumber'] as num).toInt() + 1;
    }

    final existingBalance = await _fetchClientBalance(clientName);
    final updatedBalance = existingBalance - balance;

    final invoiceData = <String, dynamic>{
      'invoiceNumber': newInvoiceNumber,
      'clientName': clientName,
      'date': selectedDate,
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

    final docRef =
        await FirebaseFirestore.instance.collection('returnInvoices').add(invoiceData);
    await docRef.update({'id': docRef.id});

    await InvoiceStockService.applyStockChanges(
      lines: products,
      restore: true,
      changeDate: selectedDate,
      changeTypeWhenRestore: 'return',
      seed: productCatalog,
    );

    final clientDocRef =
        FirebaseFirestore.instance.collection('clients').doc(clientName);

    await clientDocRef.set({
      'clientName': clientName,
      'balance': updatedBalance,
    }, SetOptions(merge: true));

    await clientDocRef.collection('returnInvoices').add({
      'invoiceId': docRef.id,
      'invoiceNumber': newInvoiceNumber,
      'date': selectedDate,
      'totalSum': totalSumFinal,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalanceSnapshot,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceType': 'return',
      'isSpecial': false,
      'products': products,
    });

    await clientDocRef.collection('balanceHistory').add({
      'enteredBalance': paidAmount,
      'balanceBefore': existingBalance,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'return',
    });

    final boxDocRef = FirebaseFirestore.instance.collection('box').doc('mainBox');

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final boxSnapshot = await transaction.get(boxDocRef);
      if (boxSnapshot.exists) {
        final current = (boxSnapshot['value'] ?? 0.0).toDouble();
        transaction.update(boxDocRef, {'value': current - paidAmount});
      } else {
        transaction.set(boxDocRef, {'value': -paidAmount});
      }
    });
    await boxDocRef.collection('changes').add({
      'date': FieldValue.serverTimestamp(),
      'value': paidAmount,
      'type': 'return',
      'name': clientName,
      'invoiceNumber': newInvoiceNumber,
    });

    return {...invoiceData, 'id': docRef.id};
  }

  static Future<double> _fetchClientBalance(String clientName) async {
    final clientDoc = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientName)
        .get();
    if (clientDoc.exists) {
      return (clientDoc['balance'] ?? 0.0).toDouble();
    }
    return 0.0;
  }
}
