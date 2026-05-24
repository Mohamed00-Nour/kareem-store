import 'package:cloud_firestore/cloud_firestore.dart';

import 'sales_invoices_fetch_service.dart';

/// Mark / list sales and return invoices flagged as special (مميزة).
class InvoiceSpecialService {
  static const salesCollection = 'invoices';
  static const returnCollection = 'returnInvoices';

  static bool isSpecial(Map<String, dynamic> invoice) =>
      invoice['isSpecial'] == true;

  static String sourceCollection(Map<String, dynamic> invoice) {
    final stored = invoice['_sourceCollection']?.toString();
    if (stored == returnCollection || stored == salesCollection) {
      return stored!;
    }
    if (invoice['invoiceType']?.toString() == 'return') {
      return returnCollection;
    }
    return salesCollection;
  }

  static String typeLabel(Map<String, dynamic> invoice) =>
      sourceCollection(invoice) == returnCollection ? 'مرتجع' : 'مبيعات';

  static Future<void> setSpecial({
    required String collection,
    required String docId,
    required String? clientName,
    required bool special,
  }) async {
    await FirebaseFirestore.instance
        .collection(collection)
        .doc(docId)
        .update({'isSpecial': special});

    final client = clientName?.trim() ?? '';
    if (client.isEmpty) return;

    final subCol =
        collection == returnCollection ? returnCollection : salesCollection;
    final subQuery = await FirebaseFirestore.instance
        .collection('clients')
        .doc(client)
        .collection(subCol)
        .where('invoiceId', isEqualTo: docId)
        .limit(1)
        .get();
    if (subQuery.docs.isNotEmpty) {
      await subQuery.docs.first.reference.update({'isSpecial': special});
    }
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialInvoices() async {
    final results = <Map<String, dynamic>>[];

    for (final collection in [salesCollection, returnCollection]) {
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .where('isSpecial', isEqualTo: true)
          .get();
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        data['_sourceCollection'] = collection;
        if (!data.containsKey('invoiceType')) {
          data['invoiceType'] =
              collection == returnCollection ? 'return' : 'sale';
        }
        results.add(data);
      }
    }

    SalesInvoicesFetchService.sortNewestFirst(results);
    return results;
  }
}
