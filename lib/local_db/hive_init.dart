import 'package:hive_flutter/hive_flutter.dart';
import 'models/product_local.dart';
import 'models/client_local.dart';
import 'models/supplier_local.dart';
import 'models/sync_queue_item.dart';
import 'models/invoice_local.dart';
import 'models/expense_local.dart';
import 'models/quote_local.dart';
import 'models/box_local.dart';
import 'models/balance_history_local.dart';
import 'models/department_local.dart';
import 'models/payment_breakdown_local.dart';

/// Box names — use these constants everywhere to avoid typos.
class HiveBoxNames {
  static const String products = 'products_cache';
  static const String clients = 'clients_cache';
  static const String suppliers = 'suppliers_cache';
  static const String syncQueue = 'sync_queue';
  static const String appMeta = 'app_meta'; // Stores lastSyncTimestamp, counters, etc.
  static const String invoices = 'invoices_cache';
  static const String returnInvoices = 'return_invoices_cache';
  static const String buyingInvoices = 'buying_invoices_cache';
  static const String quotes = 'quotes_cache';
  static const String expenses = 'expenses_cache';
  static const String box = 'box_cache';
  static const String balanceHistory = 'balance_history_cache';
  static const String departments = 'departments_cache';
}

/// Keys for the appMeta box.
class HiveMetaKeys {
  static const String lastProductSyncAt = 'lastProductSyncAt';
  static const String lastClientSyncAt = 'lastClientSyncAt';
  static const String lastSupplierSyncAt = 'lastSupplierSyncAt';
  static const String lastInvoiceSyncAt = 'lastInvoiceSyncAt';
  static const String lastReturnInvoiceSyncAt = 'lastReturnInvoiceSyncAt';
  static const String lastBuyingInvoiceSyncAt = 'lastBuyingInvoiceSyncAt';
  static const String lastExpenseSyncAt = 'lastExpenseSyncAt';
  static const String lastQuoteSyncAt = 'lastQuoteSyncAt';
  static const String lastDepartmentSyncAt = 'lastDepartmentSyncAt';

  // Local sequential invoice counters
  static const String nextSalesInvoiceNumber = 'nextSalesInvoiceNumber';
  static const String nextReturnInvoiceNumber = 'nextReturnInvoiceNumber';
  static const String nextBuyingInvoiceNumber = 'nextBuyingInvoiceNumber';
}

/// Initializes and registers all Hive adapters.
/// Call this once from [main()] before [runApp()].
Future<void> initHive() async {
  await Hive.initFlutter();

  // Register TypeAdapters
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductLocalAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ClientLocalAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SupplierLocalAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SyncQueueItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(InvoiceLocalAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(ExpenseLocalAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(QuoteLocalAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(BoxLocalAdapter());
  if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(BalanceHistoryLocalAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(DepartmentLocalAdapter());
  if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(PaymentBreakdownLocalAdapter());

  // Open all boxes on startup safely (handles corrupted cache or schema upgrades)
  await _openBoxSafely<ProductLocal>(HiveBoxNames.products);
  await _openBoxSafely<ClientLocal>(HiveBoxNames.clients);
  await _openBoxSafely<SupplierLocal>(HiveBoxNames.suppliers);
  await _openBoxSafely<SyncQueueItem>(HiveBoxNames.syncQueue);
  await _openBoxSafely(HiveBoxNames.appMeta);
  await _openBoxSafely<InvoiceLocal>(HiveBoxNames.invoices);
  await _openBoxSafely<InvoiceLocal>(HiveBoxNames.returnInvoices);
  await _openBoxSafely<InvoiceLocal>(HiveBoxNames.buyingInvoices);
  await _openBoxSafely<QuoteLocal>(HiveBoxNames.quotes);
  await _openBoxSafely<ExpenseLocal>(HiveBoxNames.expenses);
  await _openBoxSafely<BoxLocal>(HiveBoxNames.box);
  await _openBoxSafely<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
  await _openBoxSafely<DepartmentLocal>(HiveBoxNames.departments);
  await _openBoxSafely<PaymentBreakdownLocal>('paymentBreakdownsBox');
}

/// Opens a Hive box safely. If corrupted or schema changed, clears disk cache and re-opens cleanly.
Future<Box<T>> _openBoxSafely<T>(String name) async {
  if (Hive.isBoxOpen(name)) {
    try {
      return Hive.box<T>(name);
    } catch (_) {
      try {
        await Hive.box(name).close();
      } catch (_) {}
    }
  }

  try {
    return await Hive.openBox<T>(name);
  } catch (e) {
    try {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
    try {
      return await Hive.openBox<T>(name);
    } catch (_) {
      try {
        await Hive.close();
      } catch (_) {}
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
      return await Hive.openBox<T>(name);
    }
  }
}


/// Convenience accessors — use these to get open boxes from anywhere.
Box<ProductLocal> get productsBox {
  _ensureBoxOpen(HiveBoxNames.products);
  return Hive.box<ProductLocal>(HiveBoxNames.products);
}

Box<ClientLocal> get clientsBox {
  _ensureBoxOpen(HiveBoxNames.clients);
  return Hive.box<ClientLocal>(HiveBoxNames.clients);
}

Box<SupplierLocal> get suppliersBox {
  _ensureBoxOpen(HiveBoxNames.suppliers);
  return Hive.box<SupplierLocal>(HiveBoxNames.suppliers);
}

Box<SyncQueueItem> get syncQueueBox {
  _ensureBoxOpen(HiveBoxNames.syncQueue);
  return Hive.box<SyncQueueItem>(HiveBoxNames.syncQueue);
}

Box get appMetaBox {
  _ensureBoxOpen(HiveBoxNames.appMeta);
  return Hive.box(HiveBoxNames.appMeta);
}

Box<InvoiceLocal> get invoicesBox {
  _ensureBoxOpen(HiveBoxNames.invoices);
  return Hive.box<InvoiceLocal>(HiveBoxNames.invoices);
}

Box<InvoiceLocal> get returnInvoicesBox {
  _ensureBoxOpen(HiveBoxNames.returnInvoices);
  return Hive.box<InvoiceLocal>(HiveBoxNames.returnInvoices);
}

Box<InvoiceLocal> get buyingInvoicesBox {
  _ensureBoxOpen(HiveBoxNames.buyingInvoices);
  return Hive.box<InvoiceLocal>(HiveBoxNames.buyingInvoices);
}

Box<QuoteLocal> get quotesBox {
  _ensureBoxOpen(HiveBoxNames.quotes);
  return Hive.box<QuoteLocal>(HiveBoxNames.quotes);
}

Box<ExpenseLocal> get expensesBox {
  _ensureBoxOpen(HiveBoxNames.expenses);
  return Hive.box<ExpenseLocal>(HiveBoxNames.expenses);
}

Box<BoxLocal> get boxCacheBox {
  _ensureBoxOpen(HiveBoxNames.box);
  return Hive.box<BoxLocal>(HiveBoxNames.box);
}

Box<BalanceHistoryLocal> get balanceHistoryBox {
  _ensureBoxOpen(HiveBoxNames.balanceHistory);
  return Hive.box<BalanceHistoryLocal>(HiveBoxNames.balanceHistory);
}

Box<DepartmentLocal> get departmentsBox {
  _ensureBoxOpen(HiveBoxNames.departments);
  return Hive.box<DepartmentLocal>(HiveBoxNames.departments);
}

void _ensureBoxOpen(String name) {
  if (!Hive.isBoxOpen(name)) {
    throw HiveError(
      'Hive box "$name" is not open yet. Make sure `await initHive();` is called before accessing database boxes.',
    );
  }
}

