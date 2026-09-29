import '../sync/realtime_sync_service.dart';

/// Compatibility hydrator for supplier pages.
///
/// It deliberately does not recalculate or write a supplier balance. The
/// accepted local baseline plus immutable financial events own that value.
class SupplierInvoiceBalanceSyncService {
  static Future<void> syncForSupplier(String supplierId) async {
    if (supplierId.trim().isEmpty) return;
    await RealtimeSyncService.instance.startListening();
  }
}
