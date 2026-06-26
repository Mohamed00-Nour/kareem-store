import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';
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

    // Resolve oldClientId by name
    String? oldClientId;
    if (oldClient.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('clients')
          .where('clientName', isEqualTo: oldClient)
          .limit(1)
          .get();
      oldClientId = query.docs.isNotEmpty ? query.docs.first.id : oldClient;
    }

    // Resolve newClientId by name
    String? newClientId;
    if (clientName.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('clients')
          .where('clientName', isEqualTo: clientName)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        newClientId = query.docs.first.id;
      } else {
        final newRef = FirebaseFirestore.instance.collection('clients').doc();
        newClientId = newRef.id;
        await newRef.set({
          'clientName': clientName,
          'balance': 0.0,
          'id': newClientId,
        });
      }
    }

    final allLines = [...oldProducts, ...newProducts];
    final catalog =
        await InvoiceStockService.resolveCatalogVerified(lines: allLines);

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
      'clientId': newClientId,
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

    final rootRef =
        FirebaseFirestore.instance.collection(collection).doc(rootInvoiceId);
    final rootSnap = await rootRef.get();
    if (!rootSnap.exists) {
      throw StateError('الفاتورة غير موجودة في قاعدة البيانات');
    }
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
