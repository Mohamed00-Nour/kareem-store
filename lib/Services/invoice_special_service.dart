import 'package:cloud_firestore/cloud_firestore.dart';
import 'sales_invoices_fetch_service.dart';
import '../repositories/invoice_repository.dart';
import '../local_db/hive_init.dart';
import '../sync/connectivity_service.dart';

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
    // 1. Update in local Hive primary storage
    if (collection == returnCollection) {
      final local = returnInvoicesBox.get(docId);
      if (local != null) {
        local.isSpecial = special;
        await returnInvoicesBox.put(docId, local);
      }
    } else {
      final local = invoicesBox.get(docId);
      if (local != null) {
        local.isSpecial = special;
        await invoicesBox.put(docId, local);
      }
    }

    // 2. Push to Firestore if online
    if (ConnectivityService.instance.isOnline) {
      try {
        await FirebaseFirestore.instance
            .collection(collection)
            .doc(docId)
            .update({'isSpecial': special});

        final client = clientName?.trim() ?? '';
        if (client.isNotEmpty) {
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
      } catch (_) {}
    }
  }

  static Future<List<Map<String, dynamic>>> fetchSpecialInvoices() async {
    // 1. Read directly from local Hive database (0ms wait)
    final results = <Map<String, dynamic>>[];
    final sales = InvoiceRepository.instance.getAllSales().where((i) => i.isSpecial);
    for (final inv in sales) {
      final map = inv.toMap();
      map['_sourceCollection'] = salesCollection;
      results.add(map);
    }
    final returns = InvoiceRepository.instance.getAllReturns().where((i) => i.isSpecial);
    for (final inv in returns) {
      final map = inv.toMap();
      map['_sourceCollection'] = returnCollection;
      results.add(map);
    }

    SalesInvoicesFetchService.sortNewestFirst(results);
    return results;
  }
}

