import '../local_db/hive_init.dart';
import '../local_db/hive_safe_value.dart';
import 'invoice_number_utils.dart';

/// Accepted supplier payable balance: preserved baseline plus immutable events.
/// Positive means the business owes the supplier.
class SupplierBalanceStore {
  static String baseKey(String id) => 'supplierBalanceBase:$id';
  static String eventKey(String id, String operationId) =>
      'supplierBalanceEvent:$id:$operationId';

  static bool hasBase(String id) => appMetaBox.containsKey(baseKey(id));

  static double balance(String id, {double fallback = 0}) {
    if (!hasBase(id)) return fallback;
    var result = invoiceNum(appMetaBox.get(baseKey(id)));
    for (final key in appMetaBox.keys) {
      if (key.toString().startsWith('supplierBalanceEvent:$id:')) {
        result += invoiceNum((appMetaBox.get(key) as Map)['delta']);
      }
    }
    return result;
  }

  static Future<void> preserveExistingBalances() async {
    final baseWrites = <String, dynamic>{};
    for (final supplier in suppliersBox.values) {
      if (!hasBase(supplier.id)) {
        baseWrites[baseKey(supplier.id)] = supplier.balance;
      } else {
        final accepted = balance(supplier.id);
        if (supplier.balance != accepted) {
          supplier.balance = accepted;
          await supplier.save();
        }
      }
    }
    if (baseWrites.isNotEmpty) await appMetaBox.putAll(baseWrites);
    await appMetaBox.flush();
    await suppliersBox.flush();
  }

  static Future<void> initializeFromCloud(
      String id, Map<String, dynamic> data) async {
    if (hasBase(id)) return;
    await appMetaBox.put(
        baseKey(id),
        invoiceNum(data['financialBaseBalance'] ??
            data['totalBalance'] ??
            data['balance']));
    await appMetaBox.flush();
    final prefix = 'deferredSupplierEvent:$id:';
    for (final key in appMetaBox.keys.toList()) {
      if (key.toString().startsWith(prefix)) {
        await importEvent(id, key.toString().substring(prefix.length),
            Map<String, dynamic>.from(appMetaBox.get(key) as Map));
        await appMetaBox.delete(key);
      }
    }
  }

  static Future<void> importEvent(
      String id, String operationId, Map<String, dynamic> data) async {
    final safeData = hiveSafeMap(data);
    if (!hasBase(id)) {
      await appMetaBox.put('deferredSupplierEvent:$id:$operationId', safeData);
      return;
    }
    final key = eventKey(id, operationId);
    if (appMetaBox.containsKey(key)) return;
    await appMetaBox.put(key, safeData);
    await appMetaBox.flush();
    final supplier = suppliersBox.get(id);
    if (supplier != null) {
      supplier.balance = balance(id);
      await supplier.save();
    }
  }

  /// Replaces this device's provisional local event with the event that was
  /// committed by the server. This is intentionally separate from
  /// [importEvent]: normal cloud events are immutable, while a conflict-aware
  /// purchase deletion may be rebuilt from a newer cloud invoice.
  static Future<void> acceptAcknowledgedEvent(
      String id, String operationId, Map<String, dynamic> data) async {
    final safeData = hiveSafeMap(data);
    if (!hasBase(id)) {
      await appMetaBox.put('deferredSupplierEvent:$id:$operationId', safeData);
      await appMetaBox.flush();
      return;
    }
    await appMetaBox.put(eventKey(id, operationId), safeData);
    await appMetaBox.flush();
    final supplier = suppliersBox.get(id);
    if (supplier != null) {
      supplier.balance = balance(id);
      await supplier.save();
      await suppliersBox.flush();
    }
  }
}
