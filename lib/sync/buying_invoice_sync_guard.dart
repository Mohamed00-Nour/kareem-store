/// Supplier invoice copies are derived from the guarded main invoice.
String? guardedBuyingInvoiceEditId(Map<String, dynamic> payload) {
  if (payload['financialFormat'] != 2 ||
      payload['operationType'] != 'editBuyingInvoice') {
    return null;
  }
  final invoiceId = payload['invoiceId']?.toString().trim() ?? '';
  final writes = payload['cloudWrites'];
  if (invoiceId.isEmpty || writes is! List) return null;
  for (final write in writes) {
    if (write is Map &&
        write['path'] == 'buying invoices/$invoiceId' &&
        write['expectedOperationId'] is String &&
        write['expectedFinancialState'] is Map &&
        write['deleted'] != true) {
      return invoiceId;
    }
  }
  return null;
}

bool isBuyingInvoiceCopyPath(String path, String invoiceId) {
  final parts = path.split('/');
  return parts.length == 4 &&
      parts[0] == 'suppliers' &&
      parts[1].isNotEmpty &&
      parts[2] == 'buying invoices' &&
      parts[3] == invoiceId;
}

bool isRetryableBuyingInvoiceCopyConflict(
    Map<String, dynamic> payload, String? error) {
  final invoiceId = guardedBuyingInvoiceEditId(payload);
  if (invoiceId == null) return false;
  final match = RegExp(r'Concurrent change to ([^;]+); review before retrying')
      .firstMatch(error ?? '');
  final path = match?.group(1);
  if (path == null || !isBuyingInvoiceCopyPath(path, invoiceId)) return false;
  return (payload['cloudWrites'] as List)
      .any((write) => write is Map && write['path'] == path);
}
