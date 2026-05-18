import 'package:cloud_firestore/cloud_firestore.dart';

class SalesInvoicesFetchService {
  static Future<List<Map<String, dynamic>>> fetchByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay =
        DateTime(end.year, end.month, end.day, 23, 59, 59);

    final snap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay))
        .get();

    final invoices = snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();

    invoices.sort(_compareByClientThenDate);

    return invoices;
  }

  static String clientName(Map<String, dynamic> invoice) =>
      invoice['clientName']?.toString().trim() ?? '';

  /// Groups invoices by client; within each client, newest first.
  static int _compareByClientThenDate(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final clientA = clientName(a);
    final clientB = clientName(b);
    if (clientA.isEmpty && clientB.isNotEmpty) return 1;
    if (clientB.isEmpty && clientA.isNotEmpty) return -1;
    final byClient = clientA.compareTo(clientB);
    if (byClient != 0) return byClient;

    final da = invoiceDate(a);
    final db = invoiceDate(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  static Future<List<Map<String, dynamic>>> fetchToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return fetchByDateRange(start: today, end: today);
  }

  static DateTime? invoiceDate(Map<String, dynamic> invoice) {
    final date = invoice['date'];
    if (date is Timestamp) return date.toDate();
    if (date is DateTime) return date;
    return null;
  }
}
