/// Parses invoice / product numeric fields stored as [num] or [String] in Firestore.
double invoiceNum(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String invoiceAmount(dynamic value, [int fractionDigits = 2]) =>
    invoiceNum(value).toStringAsFixed(fractionDigits);
