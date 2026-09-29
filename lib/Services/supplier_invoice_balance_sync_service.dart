import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/balance_history_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/supplier_repository.dart';

/// Compatibility hydrator for supplier pages.
///
/// It deliberately does not recalculate or write a supplier balance. The
/// accepted local baseline plus immutable financial events own that value.
class SupplierInvoiceBalanceSyncService {
  static Future<void> syncForSupplier(String supplierId) async {
    if (supplierId.trim().isEmpty) return;
    final firestore = FirebaseFirestore.instance;
    final supplier =
        await firestore.collection('suppliers').doc(supplierId).get();
    if (supplier.exists) {
      await SupplierRepository.instance
          .hydrateCloud(supplierId, supplier.data());
    }
    await Future.wait([
      BalanceHistoryRepository.instance.fullSyncForSupplier(supplierId),
      InvoiceRepository.instance.syncBuyingReturnsForSupplier(supplierId),
    ]);
  }
}
