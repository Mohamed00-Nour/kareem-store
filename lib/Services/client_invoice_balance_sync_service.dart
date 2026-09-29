import '../local_db/hive_init.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../sync/local_operation_journal.dart';
import 'customer_balance_store.dart';

/// Compatibility name: hydration only. Reconnect must never repair balances.
class ClientInvoiceBalanceSyncService {
  static Future<void> syncForClient(String clientId) async {
    final fs = FirebaseFirestore.instance;
    final client = await fs.collection('clients').doc(clientId).get();
    if (client.exists)
      await ClientRepository.instance.mergeCloud(clientId, client.data()!);
    await Future.wait([
      InvoiceRepository.instance.fullSyncSales(),
      InvoiceRepository.instance.fullSyncReturns(),
      BalanceHistoryRepository.instance.fullSyncForClient(clientId),
    ]);
    // Resolve aliases only from an explicit invoiceId link.
    for (final collection in ['invoices', 'returnInvoices']) {
      final copies = await fs
          .collection('clients')
          .doc(clientId)
          .collection(collection)
          .get();
      await LocalOperationJournal.exclusive(() async {
        for (final doc in copies.docs) {
          final rootId = doc.data()['invoiceId']?.toString() ?? '';
          if (rootId.isNotEmpty && rootId != doc.id) {
            await appMetaBox.put(
                'customerInvoiceAlias:' + collection + ':' + doc.id, rootId);
          }
        }
      });
    }
    final events = await fs
        .collection('clients')
        .doc(clientId)
        .collection('financialOperations')
        .get();
    await LocalOperationJournal.exclusive(() async {
      for (final doc in events.docs) {
        await CustomerBalanceStore.importEvent(clientId, doc.id, doc.data());
      }
    });
  }
}
