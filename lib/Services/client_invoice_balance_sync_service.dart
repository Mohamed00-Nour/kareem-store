import '../sync/realtime_sync_service.dart';

/// Compatibility name: hydration only. Reconnect must never repair balances.
class ClientInvoiceBalanceSyncService {
  static Future<void> syncForClient(String clientId) async {
    if (clientId.trim().isEmpty) return;
    // Historical data is established by the one-time compatibility baseline.
    // Later changes arrive through the shared sequenced receipt listener. A
    // page open must not redownload all invoices and ledger entries.
    await RealtimeSyncService.instance.startListening();
  }
}
