import 'customer_voucher_repository.dart';
import 'supplier_voucher_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/quote_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/department_repository.dart';
import '../repositories/payment_breakdown_repository.dart';
import '../Services/invoice_number_utils.dart';
import '../local_db/hive_init.dart';

/// Orchestrates startup data sync across all repositories.
///
/// Called once after [initHive()] and [Firebase.initializeApp()] in [main()].
///
/// Strategy:
///  - Seed local invoice counters from Firestore.
///  - If the local cache is **empty** (first launch), run a full sync.
///  - If the local cache has data, run a **delta sync** (only changed docs).
class DataSyncService {
  DataSyncService._();
  static final DataSyncService instance = DataSyncService._();
  Future<void>? _activeSync;

  /// Run on app startup. Safe to call with no internet — fails silently
  /// and the local cache serves stale data until next successful sync.
  Future<void> syncOnStartup({bool includeRealtimeCollections = true}) {
    final running = _activeSync;
    if (running != null) return running;
    final future = _performSync(
      includeRealtimeCollections: includeRealtimeCollections,
    );
    _activeSync = future;
    return future.whenComplete(() {
      if (identical(_activeSync, future)) {
        _activeSync = null;
      }
    });
  }

  Future<void> _performSync({required bool includeRealtimeCollections}) async {
    try {
      // 1. Seed invoice counters so offline numbers match cloud sequence
      await LocalInvoiceCounter.seedFromFirestore();

      final bool isFirstLaunch =
          appMetaBox.get(HiveMetaKeys.lastProductSyncAt) == null;

      final backgroundOnly = <Future<void>>[
        isFirstLaunch
            ? ExpenseRepository.instance.fullSync()
            : ExpenseRepository.instance.deltaSync(),
        BoxRepository.instance.fullSync(),
        isFirstLaunch
            ? DepartmentRepository.instance.fullSync()
            : DepartmentRepository.instance.deltaSync(),
        PaymentBreakdownRepository.instance.fullSyncFromFirestore(),
      ];

      if (!includeRealtimeCollections) {
        // Products, parties, invoices, quotes and vouchers are already covered
        // by long-lived listeners. Reading those whole collections here as
        // well would charge every document twice on each application launch.
        await Future.wait(backgroundOnly);
      } else if (isFirstLaunch) {
        // First launch: pull everything from Firestore into Hive.
        await Future.wait([
          ProductRepository.instance.fullSync(),
          ClientRepository.instance.fullSync(),
          CustomerVoucherRepository.fullSync(),
          SupplierVoucherRepository.fullSync(),
          SupplierRepository.instance.fullSync(),
          InvoiceRepository.instance.fullSyncSales(),
          InvoiceRepository.instance.fullSyncReturns(),
          InvoiceRepository.instance.fullSyncBuying(),
          QuoteRepository.instance.fullSync(),
          ...backgroundOnly,
        ]);
      } else {
        // Subsequent launches: only pull what changed since last sync.
        await Future.wait([
          ProductRepository.instance.deltaSync(),
          ClientRepository.instance.deltaSync(),
          CustomerVoucherRepository.fullSync(),
          SupplierVoucherRepository.fullSync(),
          SupplierRepository.instance.deltaSync(),
          InvoiceRepository.instance.deltaSyncSales(),
          InvoiceRepository.instance.deltaSyncReturns(),
          InvoiceRepository.instance.deltaSyncBuying(),
          QuoteRepository.instance.deltaSync(),
          ...backgroundOnly,
        ]);
      }
      await appMetaBox.delete('cloudRefreshError');
    } catch (error) {
      await appMetaBox.put('cloudRefreshError', error.toString());
      // Network unavailable — local cache serves as fallback. No action needed.
    }
  }

  /// Re-sync products only.
  Future<void> resyncProducts() async {
    try {
      await ProductRepository.instance.deltaSync();
    } catch (_) {}
  }

  /// Re-sync clients only.
  Future<void> resyncClients() async {
    try {
      await ClientRepository.instance.deltaSync();
    } catch (_) {}
  }

  /// Re-sync suppliers only.
  Future<void> resyncSuppliers() async {
    try {
      await SupplierRepository.instance.deltaSync();
    } catch (_) {}
  }

  /// Re-sync invoices only.
  Future<void> resyncInvoices() async {
    try {
      await Future.wait([
        InvoiceRepository.instance.deltaSyncSales(),
        InvoiceRepository.instance.deltaSyncReturns(),
        InvoiceRepository.instance.deltaSyncBuying(),
      ]);
    } catch (_) {}
  }
}
