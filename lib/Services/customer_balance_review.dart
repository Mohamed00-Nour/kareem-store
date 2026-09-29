import '../local_db/hive_init.dart';
import '../repositories/balance_history_repository.dart';
import '../sync/cloud_snapshot_guard.dart';
import 'customer_balance_store.dart';
import 'invoice_number_utils.dart';

/// Read-only diagnostics, never a repair. Incomplete legacy caches and disputed
/// entries need evidence before choosing any adjustment.
class CustomerBalanceReview {
  static List<Map<String, dynamic>> rows() => clientsBox.values.map((client) {
        final history =
            BalanceHistoryRepository.instance.getForClient(client.id);
        final historyTotal = history.fold<double>(
            0,
            (sum, entry) =>
                sum +
                (['opening', 'sale', 'addition', 'return_payment']
                            .contains(entry.type)
                        ? 1
                        : -1) *
                    entry.enteredBalance);
        final accepted =
            CustomerBalanceStore.balance(client.id, fallback: client.balance);
        final cloud =
            appMetaBox.get('customerCloudBalance:' + client.id) as Map?;
        return <String, dynamic>{
          'id': client.id,
          'name': client.name,
          'accepted': accepted,
          'cachedHistory': historyTotal,
          'difference': accepted - historyTotal,
          'cloud': cloud == null ? null : invoiceNum(cloud['balance']),
          'pending': CloudSnapshotGuard.pendingPath('clients/' + client.id),
          'historyCount': history.length,
        };
      }).toList();
}
