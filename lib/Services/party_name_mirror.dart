import 'package:hive/hive.dart';

import '../local_db/hive_init.dart';
import '../local_db/models/invoice_local.dart';
import '../sync/local_operation_journal.dart';
import '../utils/entity_name_normalizer.dart';

/// Keeps the party name shown on local invoices in step with the customer or
/// supplier record, matched by ID.
///
/// A rename changes only the party record. Cloud invoices keep the name they
/// were saved with, so each device updates its own local copies here. Only the
/// display name changes: totals, payments, balances and IDs are never touched.
///
/// Every method except [reconcileAll] expects the caller to hold the
/// [LocalOperationJournal] lock.
class PartyNameMirror {
  PartyNameMirror._();

  static List<Box<InvoiceLocal>> get _clientBoxes => [
        if (Hive.isBoxOpen(HiveBoxNames.invoices)) invoicesBox,
        if (Hive.isBoxOpen(HiveBoxNames.returnInvoices)) returnInvoicesBox,
      ];

  static List<Box<InvoiceLocal>> get _supplierBoxes => [
        if (Hive.isBoxOpen(HiveBoxNames.buyingInvoices)) buyingInvoicesBox,
        if (Hive.isBoxOpen(HiveBoxNames.buyingReturnInvoices))
          buyingReturnInvoicesBox,
      ];

  static Future<void> applyClientName(String clientId, String name) =>
      _apply(_clientBoxes, {clientId: name}, supplier: false);

  static Future<void> applySupplierName(String supplierId, String name) =>
      _apply(_supplierBoxes, {supplierId: name}, supplier: true);

  /// Startup pass that repairs names left stale by older app versions.
  static Future<void> reconcileAll() => LocalOperationJournal.exclusive(() async {
        if (Hive.isBoxOpen(HiveBoxNames.clients)) {
          await _apply(_clientBoxes,
              {for (final c in clientsBox.values) c.id: c.name},
              supplier: false);
        }
        if (Hive.isBoxOpen(HiveBoxNames.suppliers)) {
          await _apply(_supplierBoxes,
              {for (final s in suppliersBox.values) s.id: s.name},
              supplier: true);
        }
      });

  /// Returns the current party name for a single invoice about to be stored.
  static String? currentNameFor(InvoiceLocal invoice) {
    final supplier = invoice.supplierId.trim().isNotEmpty;
    final id = supplier ? invoice.supplierId.trim() : invoice.clientId.trim();
    if (id.isEmpty) return null;
    final boxName =
        supplier ? HiveBoxNames.suppliers : HiveBoxNames.clients;
    if (!Hive.isBoxOpen(boxName)) return null;
    final name = supplier ? suppliersBox.get(id)?.name : clientsBox.get(id)?.name;
    if (name == null || name.trim().isEmpty) return null;
    final stored = supplier ? invoice.supplierName : invoice.clientName;
    return _differs(stored, name) ? name : null;
  }

  static bool _differs(String stored, String current) =>
      normalizeEntityName(stored) != normalizeEntityName(current);

  static Future<void> _apply(
      List<Box<InvoiceLocal>> boxes, Map<String, String> names,
      {required bool supplier}) async {
    if (names.isEmpty) return;
    for (final box in boxes) {
      final changed = <dynamic, InvoiceLocal>{};
      for (final key in box.keys) {
        final invoice = box.get(key);
        if (invoice == null) continue;
        final id =
            (supplier ? invoice.supplierId : invoice.clientId).trim();
        final current = names[id];
        if (id.isEmpty || current == null || current.trim().isEmpty) continue;
        final stored = supplier ? invoice.supplierName : invoice.clientName;
        if (!_differs(stored, current)) continue;
        if (supplier) {
          invoice.supplierName = current;
        } else {
          invoice.clientName = current;
        }
        changed[key] = invoice;
      }
      if (changed.isNotEmpty) {
        await box.putAll(changed);
        await box.flush();
      }
    }
  }
}
