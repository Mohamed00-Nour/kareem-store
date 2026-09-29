import 'package:cloud_firestore/cloud_firestore.dart';

import '../local_db/hive_init.dart';
import '../sync/connectivity_service.dart';
import 'supplier_operation_service.dart';

class SupplierPaymentResult {
  final double previousBalance;
  final double newBalance;
  final String historyId;

  const SupplierPaymentResult({
    required this.previousBalance,
    required this.newBalance,
    required this.historyId,
  });
}

/// Commits supplier vouchers to Hive first and uploads the same deterministic
/// operation through the durable sync queue.
class SupplierPaymentService {
  SupplierPaymentService._();

  static final SupplierPaymentService instance = SupplierPaymentService._();

  Future<int> reserveVoucherNumber() async {
    final stored = appMetaBox.get(HiveMetaKeys.nextSupplierVoucherNumber);
    final next = stored is num ? stored.toInt() : 1;
    await appMetaBox.put(HiveMetaKeys.nextSupplierVoucherNumber, next + 1);
    return next;
  }

  Future<void> refreshVoucherCounterFromCloud() async {
    if (!ConnectivityService.instance.isOnline) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('supplier_vouchers')
        .orderBy('voucherNumber', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return;
    final raw = snapshot.docs.first.data()['voucherNumber'];
    final cloudNext = raw is num ? raw.toInt() + 1 : 1;
    final stored = appMetaBox.get(HiveMetaKeys.nextSupplierVoucherNumber);
    final localNext = stored is num ? stored.toInt() : 1;
    if (cloudNext > localNext) {
      await appMetaBox.put(
        HiveMetaKeys.nextSupplierVoucherNumber,
        cloudNext,
      );
    }
  }

  Future<SupplierPaymentResult> save({
    required String supplierId,
    required String supplierName,
    required String direction,
    required double amount,
    required String description,
    required DateTime date,
    required String paymentMethod,
    required int voucherNumber,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
    if (direction != 'عليه' && direction != 'له') {
      throw ArgumentError.value(direction, 'direction');
    }

    final storedVoucher = appMetaBox.get(
      HiveMetaKeys.nextSupplierVoucherNumber,
    );
    final storedNext = storedVoucher is num ? storedVoucher.toInt() : 1;
    if (voucherNumber >= storedNext) {
      await appMetaBox.put(
        HiveMetaKeys.nextSupplierVoucherNumber,
        voucherNumber + 1,
      );
    }

    final saved = await SupplierOperationService.savePayment(
      supplierId: supplierId,
      direction: direction,
      amount: amount,
      description: description,
      date: date,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
    );
    if (ConnectivityService.instance.isOnline) {
      ConnectivityService.instance.forceSync();
    }

    return SupplierPaymentResult(
      previousBalance: saved.previousBalance,
      newBalance: saved.newBalance,
      historyId: saved.historyId,
    );
  }
}
