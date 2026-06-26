import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';
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
    final effectiveDiscountAmt = discountIsPercent
        ? totalSumBeforeDiscount * invoiceDiscount / 100
        : invoiceDiscount;
    final totalSumFinal = totalSumBeforeDiscount - effectiveDiscountAmt;

    final clientQuery = await FirebaseFirestore.instance
        .collection('clients')
        .where('clientName', isEqualTo: clientName)
        .limit(1)
        .get();
    
    DocumentReference<Map<String, dynamic>> clientDocRef;
    double existingBalance = 0.0;
    if (clientQuery.docs.isNotEmpty) {
      final doc = clientQuery.docs.first;
      clientDocRef = doc.reference;
      existingBalance = invoiceNum(doc.data()['balance']);
    } else {
      clientDocRef = FirebaseFirestore.instance.collection('clients').doc();
      await clientDocRef.set({
        'clientName': clientName,
        'balance': 0.0,
        'id': clientDocRef.id,
      });
    }

    final prep = await Future.wait<dynamic>([
      calculateTotalCost(products),
      _fetchNextReturnInvoiceNumber(),
      InvoiceStockService.resolveCatalogIfNeeded(
        lines: products,
        seed: productCatalog,
      ),
    ]);

    final totalCost = prep[0] as double;
    final newInvoiceNumber = prep[1] as int;
    final catalog = prep[2] as Map<String, ResolvedInvoiceProduct>;

    final profitMargin = -(totalSumFinal - totalCost);
    final balance = totalSumFinal - paidAmount;
    final updatedBalance = existingBalance - balance;

    final docRef = FirebaseFirestore.instance.collection('returnInvoices').doc();
    final invoiceData = <String, dynamic>{
      'id': docRef.id,
      'invoiceNumber': newInvoiceNumber,
      'clientName': clientName,
      'clientId': clientDocRef.id,
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
    final boxDocRef = FirebaseFirestore.instance.collection('box').doc('mainBox');

    await Future.wait([
      docRef.set(invoiceData),
      InvoiceStockService.applyStockChanges(
        lines: products,
        restore: true,
        changeDate: selectedDate,
        changeTypeWhenRestore: 'return',
        catalog: catalog,
      ),
      _commitReturnClientAndBox(
        clientDocRef: clientDocRef,
        boxDocRef: boxDocRef,
        clientName: clientName,
        updatedBalance: updatedBalance,
        invoiceId: docRef.id,
        newInvoiceNumber: newInvoiceNumber,
        selectedDate: selectedDate,
        totalSumFinal: totalSumFinal,
        paidAmount: paidAmount,
        balance: balance,
        previousBalanceSnapshot: previousBalanceSnapshot,
        paymentMethod: paymentMethod,
        notes: notes,
        products: products,
        existingBalance: existingBalance,
        invoiceDiscount: effectiveDiscountAmt,
      ),
    ]);

    return invoiceData;
  }

  static Future<int> _fetchNextReturnInvoiceNumber() async {
    final invoiceQuery = await FirebaseFirestore.instance
        .collection('returnInvoices')
        .orderBy('invoiceNumber', descending: true)
        .limit(1)
        .get();
    if (invoiceQuery.docs.isEmpty) return 1;
    return (invoiceQuery.docs.first['invoiceNumber'] as num).toInt() + 1;
  }

  static Future<void> _commitReturnClientAndBox({
    required DocumentReference<Map<String, dynamic>> clientDocRef,
    required DocumentReference<Map<String, dynamic>> boxDocRef,
    required String clientName,
    required double updatedBalance,
    required String invoiceId,
    required int newInvoiceNumber,
    required DateTime? selectedDate,
    required double totalSumFinal,
    required double paidAmount,
    required double balance,
    required double previousBalanceSnapshot,
    required String paymentMethod,
    required String notes,
    required List<Map<String, dynamic>> products,
    required double existingBalance,
    required double invoiceDiscount,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      clientDocRef,
      {'clientName': clientName, 'balance': updatedBalance},
      SetOptions(merge: true),
    );
    batch.set(clientDocRef.collection('returnInvoices').doc(), {
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
      'date': selectedDate,
      'totalSum': totalSumFinal,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalanceSnapshot,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': invoiceDiscount,
      'invoiceType': 'return',
      'isSpecial': false,
      'products': products,
    });
    // Entry 1: Return total (debt decrease)
    batch.set(clientDocRef.collection('balanceHistory').doc(), {
      'enteredBalance': totalSumFinal,
      'balanceBefore': existingBalance,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'return',
      'invoiceId': invoiceId,
      'invoiceNumber': newInvoiceNumber,
    });
    // Entry 2: Refund paid back (debt increase) — only if > 0
    if (paidAmount > 0) {
      batch.set(clientDocRef.collection('balanceHistory').doc(), {
        'enteredBalance': paidAmount,
        'balanceBefore': existingBalance - totalSumFinal,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'return_payment',
        'invoiceId': invoiceId,
        'invoiceNumber': newInvoiceNumber,
      });
    }
    batch.set(
      boxDocRef,
      {'value': FieldValue.increment(-paidAmount)},
      SetOptions(merge: true),
    );
    batch.set(boxDocRef.collection('changes').doc(), {
      'date': FieldValue.serverTimestamp(),
      'value': paidAmount,
      'type': 'return',
      'name': clientName,
      'invoiceNumber': newInvoiceNumber,
    });
    await batch.commit();
  }

  static Future<double> _fetchClientBalance(String clientName) async {
    final clientQuery = await FirebaseFirestore.instance
        .collection('clients')
        .where('clientName', isEqualTo: clientName)
        .limit(1)
        .get();
    if (clientQuery.docs.isNotEmpty) {
      return invoiceNum(clientQuery.docs.first.data()['balance']);
    }
    return 0.0;
  }
}
