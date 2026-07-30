import '../repositories/product_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';
import '../local_db/hive_init.dart';

/// Orchestrates startup data sync across all repositories.
///
/// Called once after [initHive()] and [Firebase.initializeApp()] in [main()].
///
/// Strategy:
///  - If the local cache is **empty** (first launch), run a full sync.
///  - If the local cache has data, run a **delta sync** (only changed docs).
class DataSyncService {
  DataSyncService._();
  static final DataSyncService instance = DataSyncService._();

  /// Run on app startup. Safe to call with no internet — fails silently
  /// and the local cache serves stale data until next successful sync.
  Future<void> syncOnStartup() async {
    try {
      final bool isFirstLaunch =
          appMetaBox.get(HiveMetaKeys.lastProductSyncAt) == null;

      if (isFirstLaunch) {
        // First launch: pull everything from Firestore.
        await Future.wait([
          ProductRepository.instance.fullSync(),
          ClientRepository.instance.fullSync(),
          SupplierRepository.instance.fullSync(),
        ]);
      } else {
        // Subsequent launches: only pull what changed since last sync.
        await Future.wait([
          ProductRepository.instance.deltaSync(),
          ClientRepository.instance.deltaSync(),
          SupplierRepository.instance.deltaSync(),
        ]);
      }
    } catch (_) {
      // Network unavailable — local cache serves as fallback. No action needed.
    }
  }

  /// Re-sync products only (e.g., after adding/editing a product).
  Future<void> resyncProducts() async {
    try {
      await ProductRepository.instance.deltaSync();
    } catch (_) {}
  }

  /// Re-sync clients only (e.g., after a balance update).
  Future<void> resyncClients() async {
    try {
      await ClientRepository.instance.deltaSync();
    } catch (_) {}
  }

  /// Re-sync suppliers only (e.g., after a supplier payment).
  Future<void> resyncSuppliers() async {
    try {
      await SupplierRepository.instance.deltaSync();
    } catch (_) {}
  }
}
