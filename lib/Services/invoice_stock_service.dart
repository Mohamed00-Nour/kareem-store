import 'package:cloud_firestore/cloud_firestore.dart';

import 'invoice_number_utils.dart';

/// Resolved Firestore product used for cost + stock updates on invoices.
class ResolvedInvoiceProduct {
  final String id;
  final String name;
  final double costPrice;
  final double quantity;

  const ResolvedInvoiceProduct({
    required this.id,
    required this.name,
    required this.costPrice,
    required this.quantity,
  });

  DocumentReference<Map<String, dynamic>> get ref =>
      FirebaseFirestore.instance.collection('products').doc(id);
}

/// Fast stock adjustments and cost totals for invoice save (batch writes, few reads).
class InvoiceStockService {
  static const int _whereInChunk = 10;
  static const int _batchOpLimit = 450;

  static String lineCatalogName(Map<String, dynamic> line) =>
      invoiceCatalogProductName(line);

  static bool _catalogCoversLines(
    Iterable<Map<String, dynamic>> lines,
    Map<String, ResolvedInvoiceProduct> catalog,
  ) {
    for (final line in lines) {
      final name = lineCatalogName(line);
      if (name.isNotEmpty && !catalog.containsKey(name)) return false;
    }
    return true;
  }

  static Map<String, ResolvedInvoiceProduct> memoryCatalogFromMaps(
    Iterable<Map<String, dynamic>> entries,
  ) {
    final map = <String, ResolvedInvoiceProduct>{};
    for (final e in entries) {
      final id = e['id']?.toString() ?? '';
      final name = e['name']?.toString() ?? '';
      if (name.isEmpty || id.isEmpty) continue;
      map[name] = ResolvedInvoiceProduct(
        id: id,
        name: name,
        costPrice: invoiceNum(e['costPrice']),
        quantity: invoiceNum(e['quantity']),
      );
    }
    return map;
  }

  static Future<Map<String, ResolvedInvoiceProduct>> resolveCatalog({
    required Iterable<Map<String, dynamic>> lines,
    Map<String, ResolvedInvoiceProduct> seed = const {},
  }) async {
    final catalog = Map<String, ResolvedInvoiceProduct>.from(seed);
    final missing = <String>{};
    for (final line in lines) {
      final name = lineCatalogName(line);
      if (name.isEmpty) continue;
      if (!catalog.containsKey(name)) missing.add(name);
    }
    if (missing.isEmpty) return catalog;

    final names = missing.toList();
    final chunkFutures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < names.length; i += _whereInChunk) {
      final end = (i + _whereInChunk > names.length)
          ? names.length
          : i + _whereInChunk;
      final chunk = names.sublist(i, end);
      chunkFutures.add(
        FirebaseFirestore.instance
            .collection('products')
            .where('name', whereIn: chunk)
            .get(),
      );
    }

    final snapshots = await Future.wait(chunkFutures);
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['name']?.toString() ?? '';
        if (name.isEmpty || catalog.containsKey(name)) continue;
        catalog[name] = ResolvedInvoiceProduct(
          id: doc.id,
          name: name,
          costPrice: invoiceNum(data['costPrice']),
          quantity: invoiceNum(data['quantity']),
        );
      }
    }
    return catalog;
  }

  static Future<Map<String, ResolvedInvoiceProduct>> resolveCatalogIfNeeded({
    required Iterable<Map<String, dynamic>> lines,
    Map<String, ResolvedInvoiceProduct> seed = const {},
  }) async {
    if (_catalogCoversLines(lines, seed)) return seed;
    return resolveCatalog(lines: lines, seed: seed);
  }

  /// Like [resolveCatalogIfNeeded] but confirms each product document exists.
  /// Re-queries by name when a cached id points to a missing document.
  static Future<Map<String, ResolvedInvoiceProduct>> resolveCatalogVerified({
    required Iterable<Map<String, dynamic>> lines,
    Map<String, ResolvedInvoiceProduct> seed = const {},
  }) async {
    final catalog = await resolveCatalogIfNeeded(lines: lines, seed: seed);
    final verified = <String, ResolvedInvoiceProduct>{};
    final names = <String>{};
    for (final line in lines) {
      final name = lineCatalogName(line);
      if (name.isNotEmpty) names.add(name);
    }

    for (final name in names) {
      var product = catalog[name];
      if (product != null && !(await product.ref.get()).exists) {
        product = null;
      }
      if (product == null) {
        final snap = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: name)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) continue;
        final doc = snap.docs.first;
        final data = doc.data();
        product = ResolvedInvoiceProduct(
          id: doc.id,
          name: name,
          costPrice: invoiceNum(data['costPrice']),
          quantity: invoiceNum(data['quantity']),
        );
      }
      verified[name] = product;
    }
    return verified;
  }

  static double computeCostTotal(
    List<Map<String, dynamic>> lines,
    Map<String, ResolvedInvoiceProduct> catalog,
  ) {
    var total = 0.0;
    for (final line in lines) {
      final name = lineCatalogName(line);
      final resolved = catalog[name];
      final amount = invoiceNum(line['amount']);
      if (amount <= 0) continue;
      final unitCost = invoiceLineHasFrozenCost(line)
          ? invoiceNum(line['costPrice'])
          : (resolved?.costPrice ?? 0.0);
      if (unitCost <= 0 && resolved == null) continue;
      total += unitCost * amount;
    }
    return total;
  }

  static Future<double> computeCostTotalAsync(
    List<Map<String, dynamic>> lines, {
    Map<String, ResolvedInvoiceProduct> seed = const {},
  }) async {
    final catalog = await resolveCatalogIfNeeded(lines: lines, seed: seed);
    return computeCostTotal(lines, catalog);
  }

  /// [restore] true = add qty back (undo sale / return), false = decrease stock.
  static Future<void> applyStockChanges({
    required List<Map<String, dynamic>> lines,
    required bool restore,
    DateTime? changeDate,
    Map<String, ResolvedInvoiceProduct> seed = const {},
    Map<String, ResolvedInvoiceProduct>? catalog,
    String changeTypeWhenRestore = 'increase',
    String changeTypeWhenDecrease = 'decrease',
  }) async {
    if (lines.isEmpty) return;

    final resolved = await resolveCatalogVerified(
      lines: lines,
      seed: catalog ?? seed,
    );

    final deltaByDocId = <String, double>{};
    final changeDateByDocId = <String, dynamic>{};
    final refByDocId = <String, DocumentReference<Map<String, dynamic>>>{};

    for (final line in lines) {
      final name = lineCatalogName(line);
      final product = resolved[name];
      if (product == null) continue;
      final amount = invoiceNum(line['amount']);
      if (amount <= 0) continue;
      deltaByDocId[product.id] = (deltaByDocId[product.id] ?? 0) + amount;
      changeDateByDocId[product.id] =
          line['date'] ?? changeDate ?? DateTime.now();
      refByDocId[product.id] = product.ref;
    }

    if (deltaByDocId.isEmpty) return;

    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (ops == 0) return;
      if (!force && ops < _batchOpLimit) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      ops = 0;
    }

    for (final entry in deltaByDocId.entries) {
      final id = entry.key;
      final delta = entry.value;
      final ref = refByDocId[id]!;
      final changeType =
          restore ? changeTypeWhenRestore : changeTypeWhenDecrease;
      final increment = restore ? delta : -delta;

      batch.update(ref, {'quantity': FieldValue.increment(increment)});
      batch.set(ref.collection('changes').doc(), {
        'date': changeDateByDocId[id],
        'amount': delta,
        'type': changeType,
      });
      ops += 2;
      if (ops >= _batchOpLimit) await commitIfNeeded(force: true);
    }

    await commitIfNeeded(force: true);
  }
}
