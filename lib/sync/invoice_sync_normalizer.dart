/// Numeric fields that must always be written to Firestore as numbers.
const invoiceSyncNumericFields = <String>{
  'totalSum',
  'paidAmount',
  'balance',
  'previousBalance',
  'invoiceDiscount',
  'profitMargin',
};

const productLineSyncNumericFields = <String>{
  'amount',
  'quantity',
  'qty',
  'cost',
  'costPrice',
  'selectedPrice',
  'total',
  'totalCost',
  'newCostPrice',
  'newSellingPrice1',
  'newSellingPrice2',
  'newSellingPrice3',
};

/// Accepts both JSON numbers and numeric strings from legacy queue payloads.
double syncDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) {
    final number = value.toDouble();
    return number.isFinite ? number : fallback;
  }
  if (value is String) {
    var text = value.trim().replaceAll(RegExp(r'\s+'), '');
    final comma = text.lastIndexOf(',');
    final dot = text.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      text = comma > dot
          ? text.replaceAll('.', '').replaceAll(',', '.')
          : text.replaceAll(',', '');
    } else if (comma >= 0) {
      final decimalDigits = text.length - comma - 1;
      text = decimalDigits == 3
          ? text.replaceAll(',', '')
          : text.replaceAll(',', '.');
    }
    final parsed = double.tryParse(text);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

int syncInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = syncDouble(value, fallback: double.nan);
    return parsed.isFinite ? parsed.toInt() : fallback;
  }
  return fallback;
}

Map<String, dynamic> normalizeProductLineForSync(Map<dynamic, dynamic> line) {
  final normalized = Map<String, dynamic>.from(line);
  for (final field in productLineSyncNumericFields) {
    if (normalized[field] != null) {
      normalized[field] = syncDouble(normalized[field]);
    }
  }
  return normalized;
}

List<dynamic> normalizeProductLinesForSync(dynamic products) {
  if (products is! List) return <dynamic>[];
  return products
      .map((product) =>
          product is Map ? normalizeProductLineForSync(product) : product)
      .toList();
}

Map<String, dynamic> normalizeInvoiceForSync(Map<dynamic, dynamic> invoice) {
  final normalized = Map<String, dynamic>.from(invoice);
  for (final field in invoiceSyncNumericFields) {
    if (normalized[field] != null) {
      normalized[field] = syncDouble(normalized[field]);
    }
  }
  if (normalized['invoiceNumber'] != null) {
    normalized['invoiceNumber'] = syncInt(normalized['invoiceNumber']);
  }
  if (normalized['products'] is List) {
    normalized['products'] =
        normalizeProductLinesForSync(normalized['products']);
  }
  return normalized;
}
