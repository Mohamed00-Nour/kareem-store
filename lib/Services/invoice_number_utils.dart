import 'package:intl/intl.dart';

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

/// Running balance after this invoice (المتبقي عليكم / للمورد).
double invoiceBalanceAfter(Map<String, dynamic> invoice) {
  final previous = invoiceNum(invoice['previousBalance']);
  final unpaid = invoiceUnpaidAmount(invoice);
  if (invoiceIsReturn(invoice) || invoiceIsSupplierPurchase(invoice)) {
    return previous - unpaid;
  }
  return previous + unpaid;
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
