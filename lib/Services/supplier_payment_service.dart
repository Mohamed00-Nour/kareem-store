import 'package:cloud_firestore/cloud_firestore.dart';

import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/box_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';

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

    final supplier = SupplierRepository.instance.getById(supplierId);
    final previousBalance =
        BalanceHistoryRepository.instance.calculateSupplierBalance(
      supplierId,
      fallback: supplier?.balance ?? 0.0,
    );
    final isIncrease = direction == 'له';
    final newBalance = previousBalance + (isIncrease ? amount : -amount);
    final operationStamp = DateTime.now().microsecondsSinceEpoch;
    final historyId =
        'supplier_voucher_${supplierId}_${voucherNumber}_$operationStamp';
    final voucherId = '${historyId}_voucher';
    final cleanDescription = description.trim();
    final notes = [
      'سند $direction رقم $voucherNumber',
      if (cleanDescription.isNotEmpty) cleanDescription,
    ].join(' - ');

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

    await SupplierRepository.instance.updateLocalBalance(
      supplierId,
      newBalance,
    );
    await BalanceHistoryRepository.instance.upsertLocal(
      BalanceHistoryLocal(
        id: historyId,
        parentId: supplierId,
        parentType: 'supplier',
        enteredBalance: amount,
        balanceBefore: previousBalance,
        type: 'voucher',
        direction: direction,
        notes: notes,
        timestamp: date,
      ),
    );

    if (!isIncrease) {
      await BoxRepository.instance.decrement(amount);
    }

    await SyncQueueManager.instance.enqueue(
      operationType: 'adjustSupplierBalance',
      payload: {
        'supplierId': supplierId,
        'supplierName': supplierName,
        'amount': amount,
        'isAddition': isIncrease,
        'direction': direction,
        'newBalance': newBalance,
        'historyId': historyId,
        'voucherId': voucherId,
        'voucherNumber': voucherNumber,
        'paymentMethod': paymentMethod,
        'description': cleanDescription,
        'logEntry': {
          'enteredBalance': amount,
          'balanceBefore': previousBalance,
          'type': 'voucher',
          'direction': direction,
          'notes': notes,
          'voucherId': voucherId,
          'voucherNumber': voucherNumber,
          'paymentMethod': paymentMethod,
          'timestamp': date.toIso8601String(),
        },
      },
    );
    if (ConnectivityService.instance.isOnline) {
      ConnectivityService.instance.forceSync();
    }

    return SupplierPaymentResult(
      previousBalance: previousBalance,
      newBalance: newBalance,
      historyId: historyId,
    );
  }
}
