import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../repositories/product_repository.dart';
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

    // 1. Resolve from local Hive productsBox first (instant, zero network)
    for (final line in lines) {
      final name = lineCatalogName(line);
      if (name.isEmpty || catalog.containsKey(name)) continue;
      final localProd = ProductRepository.instance.findByName(name);
      if (localProd != null) {
        catalog[name] = ResolvedInvoiceProduct(
          id: localProd.id,
          name: localProd.name,
          costPrice: localProd.costPrice,
          quantity: localProd.quantity,
        );
      } else {
        missing.add(name);
      }
    }

    if (missing.isEmpty) return catalog;

    // 2. Only query Firestore if missing from local cache
    try {
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
    } catch (_) {
      // Offline fallback
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

    // Use local Hive-only catalog resolution — never blocks on Firestore reads
    final resolved = catalog ?? await resolveCatalogIfNeeded(
      lines: lines,
      seed: seed,
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

    // 1. Immediately apply stock changes to local Hive productsBox (<10ms UI update)
    for (final entry in deltaByDocId.entries) {
      final id = entry.key;
      final delta = entry.value;
      final increment = restore ? delta : -delta;
      final localProd = productsBox.get(id);
      if (localProd != null) {
        localProd.quantity += increment;
        localProd.updatedAt = DateTime.now();
        await localProd.save();
      }
    }
    // Note: Firestore update is executed atomically via BatchSyncEngine via SyncQueueManager
  }
}

