import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../local_db/hive_init.dart';

/// Parses invoice / product numeric fields stored as [num] or [String] in Firestore.
double invoiceNum(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

final _moneyFull = NumberFormat('#,##0.00', 'en_US');
final _moneyInt = NumberFormat('#,##0', 'en_US');

/// Formats money/qty for display: 1.00 → 1, 1.5 → 1.5, 1250 → 1,250.
String invoiceAmount(dynamic value, [int maxFractionDigits = 2]) {
  final n = invoiceNum(value);
  if (maxFractionDigits <= 0 || n == n.roundToDouble()) {
    return _moneyInt.format(n);
  }
  if (maxFractionDigits == 1) {
    if (n == n.roundToDouble()) {
      return n.toStringAsFixed(0);
    }
    return n.toStringAsFixed(1);
  }
  if (n == n.roundToDouble()) {
    return _moneyInt.format(n);
  }
  var s = _moneyFull.format(n);
  while (s.contains('.') && s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Quantity on invoice lines (0 or 1 decimal place).
String invoiceQty(dynamic value) => invoiceAmount(value, 1);

/// Resolves the selling price stored on an invoice line.
///
/// Current invoices use [selectedPrice], while some older/imported rows use
/// [price] or another unit-price alias. If none contains a positive value, the
/// original unit price is reconstructed from the stored line total and
/// quantity. Line-level discounts are reversed because [total] is saved after
/// applying the discount.
double invoiceLineUnitPrice(Map<String, dynamic> line) {
  const priceKeys = <String>[
    'selectedPrice',
    'unitPrice',
    'price',
    'salePrice',
    'sellingPrice',
  ];

  for (final key in priceKeys) {
    final price = invoiceNum(line[key]);
    if (price > 0) return price;
  }

  final quantity = invoiceNum(line['amount'] ?? line['quantity']);
  if (quantity <= 0) return 0.0;

  var lineTotal = invoiceNum(
    line['total'] ?? line['lineTotal'] ?? line['totalPrice'],
  );
  if (lineTotal <= 0) return 0.0;

  final discount = invoiceNum(line['discount']);
  if (discount > 0) {
    if (line['discountIsPercent'] == true) {
      final remainingRatio = 1 - (discount / 100);
      if (remainingRatio > 0) lineTotal /= remainingRatio;
    } else {
      lineTotal += discount;
    }
  }

  return lineTotal / quantity;
}

/// True for return invoices ([invoiceType] == return).
bool invoiceIsReturn(Map<String, dynamic> invoice) {
  return invoice['invoiceType']?.toString() == 'return';
}

/// Purchase invoice tied to a supplier (not a client sale).
bool invoiceIsSupplierPurchase(Map<String, dynamic> invoice) {
  final supplier = invoice['supplierName']?.toString().trim() ?? '';
  if (supplier.isEmpty) return false;
  final client = invoice['clientName']?.toString().trim() ?? '';
  return client.isEmpty;
}

/// Unpaid portion of this invoice (إجمالي − المدفوع).
double invoiceUnpaidAmount(Map<String, dynamic> invoice) {
  return invoiceNum(invoice['totalSum']) - invoiceNum(invoice['paidAmount']);
}

/// Resolves invoice discount: uses stored [invoiceDiscount] if > 0,
/// otherwise calculates difference between sum of product totals and [totalSum].
double invoiceResolveDiscount(Map<String, dynamic> invoice) {
  final stored = invoiceNum(invoice['invoiceDiscount']);
  if (stored > 0) return stored;
  final totalSum = invoiceNum(invoice['totalSum']);
  final products = invoice['products'] as List<dynamic>? ?? [];
  var productsSum = 0.0;
  for (final item in products) {
    if (item is! Map) continue;
    final itemTotal = invoiceNum(item['total'] ?? item['totalCost']);
    productsSum += itemTotal;
  }
  final diff = productsSum - totalSum;
  if (diff > 0.01) return diff;
  return 0.0;
}
/// Synced client total owed — same [balance] on all invoices (المتبقي عليكم).
double invoiceClientRemainingOwed(Map<String, dynamic> invoice) {
  if (invoice.containsKey('_computedRemainingOwed') && invoice['_computedRemainingOwed'] != null) {
    return invoiceNum(invoice['_computedRemainingOwed']);
  }
  if (invoice.containsKey('currentClientBalance') && invoice['currentClientBalance'] != null) {
    return invoiceNum(invoice['currentClientBalance']);
  }
  if (invoice.containsKey('previousBalance') && invoice['previousBalance'] != null) {
    final prev = invoiceNum(invoice['previousBalance']);
    final unpaid = invoiceUnpaidAmount(invoice);
    final isReturn = invoiceIsReturn(invoice);
    return isReturn ? (prev - unpaid) : (prev + unpaid);
  }
  return invoiceNum(invoice['balance']);
}

/// Synced supplier running balance — same [balance] on all buying invoices.
double invoiceSupplierRemainingOwed(Map<String, dynamic> invoice) {
  if (invoice.containsKey('_computedRemainingOwed') && invoice['_computedRemainingOwed'] != null) {
    return invoiceNum(invoice['_computedRemainingOwed']);
  }
  if (invoice.containsKey('currentSupplierBalance') && invoice['currentSupplierBalance'] != null) {
    return invoiceNum(invoice['currentSupplierBalance']);
  }
  if (invoice.containsKey('previousBalance') && invoice['previousBalance'] != null) {
    final prev = invoiceNum(invoice['previousBalance']);
    final unpaid = invoiceUnpaidAmount(invoice);
    final isReturn = invoiceIsReturn(invoice);
    return isReturn ? (prev - unpaid) : (prev + unpaid);
  }
  return invoiceNum(invoice['balance']);
}

/// Calculates previous balance based on stored historical previousBalance or dynamic calculation fallback.
double invoiceDynamicPreviousBalance(Map<String, dynamic> invoice) {
  if (invoice.containsKey('_computedPrevBalance') && invoice['_computedPrevBalance'] != null) {
    return invoiceNum(invoice['_computedPrevBalance']);
  }
  if (invoice.containsKey('previousBalance') && invoice['previousBalance'] != null) {
    return invoiceNum(invoice['previousBalance']);
  }
  final isSupplier = invoiceIsSupplierPurchase(invoice);
  final liveBalance = isSupplier
      ? invoiceSupplierRemainingOwed(invoice)
      : invoiceClientRemainingOwed(invoice);
  final unpaid = invoiceUnpaidAmount(invoice);
  final isReturn = invoiceIsReturn(invoice);

  if (isReturn) {
    return liveBalance + unpaid;
  } else {
    return liveBalance - unpaid;
  }
}

/// Running balance after this invoice (المتبقي عليكم / للمورد).
double invoiceBalanceAfter(Map<String, dynamic> invoice) {
  final isSupplier = invoiceIsSupplierPurchase(invoice);
  return isSupplier
      ? invoiceSupplierRemainingOwed(invoice)
      : invoiceClientRemainingOwed(invoice);
}

/// Product line label on invoices: [customProductName] if set, else catalog [product],
/// plus optional per-line note ([barcodeNote]).
String invoiceProductName(dynamic product) {
  if (product is! Map) {
    return product?.toString().trim() ?? '';
  }
  final map = product is Map<String, dynamic>
      ? product
      : Map<String, dynamic>.from(product);
  final catalogName = map['product']?.toString().trim() ?? '';
  final customName = map['customProductName']?.toString().trim() ?? '';
  final name = customName.isNotEmpty ? customName : catalogName;
  final note = map['barcodeNote']?.toString().trim() ?? '';
  if (note.isEmpty) return name;
  return '$name $note';
}

/// Catalog product name used for stock / Firestore lookups (not [customProductName]).
String invoiceCatalogProductName(dynamic product) {
  if (product is! Map) return product?.toString().trim() ?? '';
  final map = product is Map<String, dynamic>
      ? product
      : Map<String, dynamic>.from(product);
  return map['product']?.toString().trim() ?? '';
}

/// True when [costPrice] was stored on the invoice line at sale time.
bool invoiceLineHasFrozenCost(Map<String, dynamic> line) =>
    line.containsKey('costPrice') && line['costPrice'] != null;

/// Unit cost for reports: frozen line [costPrice], else optional catalog fallback.
double invoiceLineUnitCost(
  Map<String, dynamic> line, {
  double? catalogUnitCost,
}) {
  if (invoiceLineHasFrozenCost(line)) {
    return invoiceNum(line['costPrice']);
  }
  return catalogUnitCost ?? 0.0;
}

/// Strips internal profit fields before customer-facing PDF export.
Map<String, dynamic> invoiceForPdfExport(Map<String, dynamic> raw) {
  final out = Map<String, dynamic>.from(raw);
  out.remove('profitMargin');
  return out;
}

/// Line cost (unit × quantity) for profit reports.
double invoiceLineTotalCost(
  Map<String, dynamic> line, {
  double? catalogUnitCost,
}) {
  final qty = invoiceNum(line['amount']);
  if (qty <= 0) return 0.0;
  return invoiceLineUnitCost(line, catalogUnitCost: catalogUnitCost) *
      qty;
}

/// Local sequential invoice number manager.
///
/// Eliminates slow blocking Firestore `orderBy('invoiceNumber', descending: true).limit(1)`
/// queries on every invoice save.
class LocalInvoiceCounter {
  LocalInvoiceCounter._();

  static String _metaKey(String type) {
    switch (type.toLowerCase()) {
      case 'return':
        return HiveMetaKeys.nextReturnInvoiceNumber;
      case 'buying':
        return HiveMetaKeys.nextBuyingInvoiceNumber;
      case 'sale':
      case 'sales':
      default:
        return HiveMetaKeys.nextSalesInvoiceNumber;
    }
  }

  /// Get the next sequential invoice number and increments the local counter.
  /// Zero network latency.
  static int nextNumber(String type) {
    final key = _metaKey(type);
    final current = _getCurrentOrLocalMax(key, type);
    final next = current + 1;
    appMetaBox.put(key, next);
    return next;
  }

  /// Peeks the next number without incrementing.
  static int peekNextNumber(String type) {
    final key = _metaKey(type);
    final current = _getCurrentOrLocalMax(key, type);
    return current + 1;
  }

  static int _getCurrentOrLocalMax(String key, String type) {
    int current = (appMetaBox.get(key) as num?)?.toInt() ?? 0;
    final localBoxMax = _getMaxFromLocalBoxes(type);
    if (localBoxMax > current) {
      current = localBoxMax;
      appMetaBox.put(key, current);
    }
    return current;
  }

  static int _getMaxFromLocalBoxes(String type) {
    try {
      switch (type.toLowerCase()) {
        case 'return':
          if (!returnInvoicesBox.isOpen) return 0;
          return returnInvoicesBox.values
              .fold<int>(0, (max, inv) => inv.invoiceNumber > max ? inv.invoiceNumber : max);
        case 'buying':
          if (!buyingInvoicesBox.isOpen) return 0;
          return buyingInvoicesBox.values
              .fold<int>(0, (max, inv) => inv.invoiceNumber > max ? inv.invoiceNumber : max);
        case 'sale':
        case 'sales':
        default:
          if (!invoicesBox.isOpen) return 0;
          return invoicesBox.values
              .fold<int>(0, (max, inv) => inv.invoiceNumber > max ? inv.invoiceNumber : max);
      }
    } catch (_) {
      return 0;
    }
  }

  /// Seeds the local counters from Firestore once on startup or when empty.
  static Future<void> seedFromFirestore() async {
    // 0. Initial seed from local Hive cache
    _getCurrentOrLocalMax(HiveMetaKeys.nextSalesInvoiceNumber, 'sale');
    _getCurrentOrLocalMax(HiveMetaKeys.nextReturnInvoiceNumber, 'return');
    _getCurrentOrLocalMax(HiveMetaKeys.nextBuyingInvoiceNumber, 'buying');

    try {
      final fs = FirebaseFirestore.instance;

      // 1. Sales invoices
      final salesQuery = await fs
          .collection('invoices')
          .orderBy('invoiceNumber', descending: true)
          .limit(1)
          .get();
      if (salesQuery.docs.isNotEmpty) {
        final remoteMax = (salesQuery.docs.first['invoiceNumber'] as num?)?.toInt() ?? 0;
        final currentLocal = _getCurrentOrLocalMax(HiveMetaKeys.nextSalesInvoiceNumber, 'sale');
        if (remoteMax > currentLocal) {
          await appMetaBox.put(HiveMetaKeys.nextSalesInvoiceNumber, remoteMax);
        }
      }

      // 2. Return invoices
      final returnQuery = await fs
          .collection('returnInvoices')
          .orderBy('invoiceNumber', descending: true)
          .limit(1)
          .get();
      if (returnQuery.docs.isNotEmpty) {
        final remoteMax = (returnQuery.docs.first['invoiceNumber'] as num?)?.toInt() ?? 0;
        final currentLocal = _getCurrentOrLocalMax(HiveMetaKeys.nextReturnInvoiceNumber, 'return');
        if (remoteMax > currentLocal) {
          await appMetaBox.put(HiveMetaKeys.nextReturnInvoiceNumber, remoteMax);
        }
      }

      // 3. Buying invoices
      final buyingQuery = await fs
          .collection('buying invoices')
          .orderBy('invoiceNumber', descending: true)
          .limit(1)
          .get();
      if (buyingQuery.docs.isNotEmpty) {
        final remoteMax = (buyingQuery.docs.first['invoiceNumber'] as num?)?.toInt() ?? 0;
        final currentLocal = _getCurrentOrLocalMax(HiveMetaKeys.nextBuyingInvoiceNumber, 'buying');
        if (remoteMax > currentLocal) {
          await appMetaBox.put(HiveMetaKeys.nextBuyingInvoiceNumber, remoteMax);
        }
      }
    } catch (_) {
      // Offline on startup — local Hive fallback already applied above
    }
  }
}
