import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';

/// Delete / lookup sales invoices in [invoices] and client subcollections.
class SalesInvoiceActionsService {
  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      findClientSubInvoice({
    required String clientId,
    required String rootInvoiceId,
  }) async {
    final byField = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .where('invoiceId', isEqualTo: rootInvoiceId)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first;

    final all = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .get();
    for (final doc in all.docs) {
      if (doc.data()['invoiceId']?.toString() == rootInvoiceId) {
        return doc;
      }
    }
    return null;
  }

  /// Root invoice id (prefers [invoiceId] over embedded [id]).
  static String rootInvoiceIdFrom(Map<String, dynamic> invoice) {
    final fromField = invoice['invoiceId']?.toString().trim() ?? '';
    if (fromField.isNotEmpty) return fromField;
    return invoice['id']?.toString().trim() ?? '';
  }

  /// Loads the authoritative root invoice for edit mode.
  static Future<Map<String, dynamic>> buildEditPayload(
    Map<String, dynamic> invoice, {
    String? clientSubDocId,
  }) async {
    final collection = InvoiceSpecialService.sourceCollection(invoice);
    final rootId = rootInvoiceIdFrom(invoice);

    var payload = Map<String, dynamic>.from(invoice);
    payload['_sourceCollection'] = collection;
    if (clientSubDocId != null && clientSubDocId.isNotEmpty) {
      payload['_clientSubDocId'] = clientSubDocId;
    }
    if (rootId.isEmpty) return payload;

    final rootSnap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(rootId)
        .get();
    if (rootSnap.exists) {
      payload = {
        ...rootSnap.data()!,
        'id': rootId,
        '_sourceCollection': collection,
        if (clientSubDocId != null && clientSubDocId.isNotEmpty)
          '_clientSubDocId': clientSubDocId,
      };
    } else {
      payload['id'] = rootId;
      payload['_sourceCollection'] = collection;
    }
    return payload;
  }

  /// Deletes root invoice, matching client copy, restores stock, updates balance.
  static Future<void> deleteSalesInvoice({
    required Map<String, dynamic> invoice,
    required String rootInvoiceId,
  }) async {
    final clientId = invoice['clientName']?.toString() ?? '';
    final products = List<Map<String, dynamic>>.from(
      (invoice['products'] as List?) ?? [],
    );

    for (final product in products) {
      final name = product['product']?.toString() ?? '';
      if (name.isEmpty) continue;
      final amount = invoiceNum(product['amount']);
      if (amount <= 0) continue;

      final q = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: name)
          .get();
      for (final doc in q.docs) {
        final qty = (doc['quantity'] as num?)?.toDouble() ?? 0;
        await FirebaseFirestore.instance
            .collection('products')
            .doc(doc.id)
            .update({'quantity': qty + amount});
        await FirebaseFirestore.instance
            .collection('products')
            .doc(doc.id)
            .collection('changes')
            .add({
          'date': DateTime.now(),
          'amount': amount,
          'type': 'increase',
        });
      }
    }

    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(rootInvoiceId)
        .delete();

    if (clientId.isEmpty) return;

    final clientSub = await findClientSubInvoice(
      clientId: clientId,
      rootInvoiceId: rootInvoiceId,
    );
    if (clientSub != null) {
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .collection('invoices')
          .doc(clientSub.id)
          .delete();

      final clientDoc =
          FirebaseFirestore.instance.collection('clients').doc(clientId);
      final snap = await clientDoc.get();
      if (snap.exists) {
        final totalSum = invoiceNum(invoice['totalSum']);
        final current = invoiceNum(snap.data()?['balance']);
        await clientDoc.update({'balance': current - totalSum});
      }
    }
  }
}
