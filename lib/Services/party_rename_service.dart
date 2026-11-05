import 'dart:async';

import '../local_db/hive_init.dart';
import '../sync/connectivity_service.dart';
import '../utils/entity_name_normalizer.dart';
import 'customer_operation_service.dart';
import 'supplier_operation_service.dart';

class PartyRenameException implements Exception {
  final String message;
  PartyRenameException(this.message);

  @override
  String toString() => message;
}

/// Renames customers and suppliers offline-first.
///
/// The new name is saved on this device immediately and uploaded through the
/// sync queue, like invoices. Only the customer/supplier record changes (plus
/// legacy invoices without a party ID); balances, stock and cash are never
/// part of a rename.
class PartyRenameService {
  PartyRenameService._();

  static Future<void> renameClient({
    required String oldClientId,
    required String newName,
  }) async {
    final cleaned = cleanEntityName(newName);
    if (cleaned.isEmpty) {
      throw PartyRenameException('الاسم فارغ');
    }
    final client = clientsBox.get(oldClientId);
    if (client == null) {
      throw PartyRenameException('العميل غير موجود');
    }
    if (cleaned == client.name) return;
    final key = partyNameKey(cleaned);
    final taken = clientsBox.values.any(
        (other) => other.id != oldClientId && partyNameKey(other.name) == key);
    if (taken) {
      throw PartyRenameException('يوجد عميل بهذا الاسم بالفعل');
    }
    await CustomerOperationService.renameClient(oldClientId, cleaned);
    unawaited(ConnectivityService.instance.forceSync());
  }

  static Future<void> renameSupplier({
    required String supplierId,
    required String newName,
  }) async {
    final cleaned = cleanEntityName(newName);
    if (cleaned.isEmpty) {
      throw PartyRenameException('الاسم فارغ');
    }
    final supplier = suppliersBox.get(supplierId);
    if (supplier == null) {
      throw PartyRenameException('المورد غير موجود');
    }
    if (cleaned == supplier.name) return;
    final key = partyNameKey(cleaned);
    final taken = suppliersBox.values.any(
        (other) => other.id != supplierId && partyNameKey(other.name) == key);
    if (taken) {
      throw PartyRenameException('يوجد مورد بهذا الاسم بالفعل');
    }
    await SupplierOperationService.renameSupplier(supplierId, cleaned);
    unawaited(ConnectivityService.instance.forceSync());
  }
}
