import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoice_number_utils.dart';
import 'invoice_special_service.dart';
import 'client_invoice_running_balance_service.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../sync/connectivity_service.dart';
import 'customer_operation_service.dart';
import 'customer_balance_store.dart';

/// Delete / lookup sales invoices in [invoices] and client subcollections.
class SalesInvoiceActionsService {
  /// Returns the invoice with the exact running-balance fields used by the
  /// client invoices page. All data is read from the same local repositories,
  /// so this also works while offline.
  static Map<String, dynamic> buildClientPagePayload(
    Map<String, dynamic> invoice,
  ) {
    final fallback = Map<String, dynamic>.from(invoice);
    final rootId = rootInvoiceIdFrom(fallback);
    final clientName = fallback['clientName']?.toString().trim() ?? '';
    var clientId = fallback['clientId']?.toString().trim() ?? '';

    final localClient = (clientId.isNotEmpty
            ? ClientRepository.instance.getById(clientId)
            : null) ??
        ClientRepository.instance.findByName(clientName);
    clientId = localClient?.id ?? clientId;
    if (clientId.isEmpty) return fallback;

    final sales = InvoiceRepository.instance
        .getSalesByClient(clientId, clientName: clientName)
        .map((item) => Map<String, dynamic>.from(item.toMap()))
        .toList();
    final returns = InvoiceRepository.instance
        .getReturnsByClient(clientId, clientName: clientName)
        .map((item) => Map<String, dynamic>.from(item.toMap()))
        .toList();
    final payments = BalanceHistoryRepository.instance
        .getForClient(clientId)
        .where((item) => item.type != 'sale' && item.type != 'return')
        .map((item) => Map<String, dynamic>.from(item.toMap()))
        .toList();

    final isReturn = invoiceIsReturn(fallback) ||
        fallback['_sourceCollection']?.toString() == 'returnInvoices';
    final candidates = isReturn ? returns : sales;

    bool isTarget(Map<String, dynamic> candidate) {
      final candidateId = rootInvoiceIdFrom(candidate);
      if (rootId.isNotEmpty && candidateId == rootId) return true;
      final invoiceNumber = fallback['invoiceNumber']?.toString().trim() ?? '';
      return rootId.isEmpty &&
          invoiceNumber.isNotEmpty &&
          candidate['invoiceNumber']?.toString().trim() == invoiceNumber;
    }

    var targetIndex = candidates.indexWhere(isTarget);
    if (targetIndex < 0) {
      candidates.add(fallback);
      targetIndex = candidates.length - 1;
    }

    ClientInvoiceRunningBalanceService.apply(
      salesInvoices: sales,
      returnInvoices: returns,
      payments: payments,
      initialBalance: CustomerBalanceStore.hasBase(clientId)
          ? ClientInvoiceRunningBalanceService.carryForward(
              currentBalance: ClientRepository.instance
                  .computeLiveBalanceFromHive(clientId),
              salesInvoices: sales,
              returnInvoices: returns,
              payments: payments)
          : 0,
    );

    final clientPageData = candidates[targetIndex];
    return <String, dynamic>{
      ...fallback,
      ...clientPageData,
      if (rootId.isNotEmpty) 'id': rootId,
      'clientId': clientId,
    };
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> findClientSubInvoice({
    required String clientId,
    required String rootInvoiceId,
  }) async {
    final byField = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .where('invoiceId', isEqualTo: rootInvoiceId)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first;

    final all = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('invoices')
        .get();
    for (final doc in all.docs) {
      if (doc.data()['invoiceId']?.toString() == rootInvoiceId) {
        return doc;
      }
    }
    return null;
  }

  /// Root invoice id (prefers [invoiceId] over embedded [id]).
  static String rootInvoiceIdFrom(Map<String, dynamic> invoice) {
    final fromField = invoice['invoiceId']?.toString().trim() ?? '';
    if (fromField.isNotEmpty) return fromField;
    return invoice['id']?.toString().trim() ?? '';
  }

  /// Loads the authoritative root invoice for edit mode.
  static Future<Map<String, dynamic>> buildEditPayload(
    Map<String, dynamic> invoice, {
    String? clientSubDocId,
  }) async {
    final collection = InvoiceSpecialService.sourceCollection(invoice);
    final rootId = rootInvoiceIdFrom(invoice);

    var payload = Map<String, dynamic>.from(invoice);
    payload['_sourceCollection'] = collection;
    if (clientSubDocId != null && clientSubDocId.isNotEmpty) {
      payload['_clientSubDocId'] = clientSubDocId;
    }
    if (rootId.isEmpty) return payload;

    final local = collection == 'returnInvoices'
        ? InvoiceRepository.instance.getReturnById(rootId)
        : InvoiceRepository.instance.getSaleById(rootId);
    if (local == null)
      throw StateError('Invoice must be cached before editing');
    return {
      ...payload,
      ...local.toMap(),
      'id': rootId,
      '_sourceCollection': collection
    };
  }

  /// Deletes root invoice, matching client copy, restores stock, updates balance in Hive first.

  static Future<void> deleteSalesInvoice({
    required Map<String, dynamic> invoice,
    required String rootInvoiceId,
  }) async {
    await CustomerOperationService.deleteInvoice(rootInvoiceId,
        isReturn: invoiceIsReturn(invoice));
    ConnectivityService.instance.forceSync();
  }
}
