import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';
import 'invoice_repository.dart';

/// Repository for Client & Supplier Balance History entries.
///
/// READ: Served immediately from Hive `balanceHistoryBox`.
/// WRITE: Stored locally, synced in background.
class BalanceHistoryRepository {
  BalanceHistoryRepository._();
  static final BalanceHistoryRepository instance = BalanceHistoryRepository._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static String _boxKey(String parentType, String parentId, String docId) =>
      '${parentType}_${parentId}_$docId';

  static int _typePriority(String type) {
    switch (type) {
      case 'opening':
        return 0;
      case 'sale':
      case 'buying':
        return 1;
      case 'sale_payment':
      case 'buying_payment':
        return 2;
      case 'return':
        return 3;
      case 'return_payment':
        return 4;
      case 'addition':
        return 5;
      case 'deduction':
      case 'voucher':
        return 6;
      default:
        return 7;
    }
  }

  static int _invoiceNumber(BalanceHistoryLocal item) =>
      int.tryParse(item.invoiceNumber.trim()) ?? 0;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _compareHistoryAscending(
    BalanceHistoryLocal a,
    BalanceHistoryLocal b,
  ) {
    final typeA = a.type;
    final typeB = b.type;

    if (typeA == 'opening' && typeB != 'opening') return -1;
    if (typeB == 'opening' && typeA != 'opening') return 1;

    final dayCmp = _dateOnly(a.timestamp).compareTo(_dateOnly(b.timestamp));
    if (dayCmp != 0) return dayCmp;

    final invA = _invoiceNumber(a);
    final invB = _invoiceNumber(b);
    if (invA > 0 && invB > 0 && invA != invB) {
      return invA.compareTo(invB);
    }

    final timeCmp = a.timestamp.compareTo(b.timestamp);
    if (timeCmp != 0) return timeCmp;

    final priorityCmp = _typePriority(typeA).compareTo(_typePriority(typeB));
    if (priorityCmp != 0) return priorityCmp;

    return a.id.compareTo(b.id);
  }

  List<BalanceHistoryLocal> getForClient(String clientId) {
    final cId = clientId.trim();
    var list = balanceHistoryBox.values
        .where((e) => e.parentType == 'client' && e.parentId == cId)
        .toList();

    final activeSales = InvoiceRepository.instance.getSalesByClient(cId);
    final activeReturns = InvoiceRepository.instance.getReturnsByClient(cId);

    bool matchesInvoice(
      BalanceHistoryLocal entry,
      String invoiceId,
      String invoiceNumber,
    ) {
      return (invoiceId.isNotEmpty &&
              (entry.invoiceId == invoiceId ||
                  entry.id == invoiceId ||
                  entry.id.startsWith(invoiceId))) ||
          (invoiceNumber.isNotEmpty &&
              (entry.invoiceNumber == invoiceNumber ||
                  entry.id.contains(invoiceNumber)));
    }

    // Auto-populate missing history entries for active local sales invoices in Hive
    for (final inv in activeSales) {
      final invId = inv.id.trim();
      final invNum = inv.invoiceNumber.toString().trim();
      final saleEntries = list
          .where(
            (e) => e.type == 'sale' && matchesInvoice(e, invId, invNum),
          )
          .toList();
      final paymentEntries = list
          .where(
            (e) => e.type == 'sale_payment' && matchesInvoice(e, invId, invNum),
          )
          .toList();

      if (saleEntries.isEmpty) {
        final saleHist = BalanceHistoryLocal(
          id: '${inv.id}_sale',
          parentId: cId,
          parentType: 'client',
          enteredBalance: inv.totalSum,
          balanceBefore: inv.previousBalance,
          type: 'sale',
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber.toString(),
          timestamp: inv.date,
        );
        upsertLocal(saleHist);
        list.add(saleHist);
      } else {
        final saleEntry = saleEntries.first;
        if ((saleEntry.enteredBalance - inv.totalSum).abs() > 0.001) {
          saleEntry.enteredBalance = inv.totalSum;
          upsertLocal(saleEntry);
        }
      }

      if (inv.paidAmount > 0 && paymentEntries.isEmpty) {
        final payHist = BalanceHistoryLocal(
          id: '${inv.id}_pay',
          parentId: cId,
          parentType: 'client',
          enteredBalance: inv.paidAmount,
          balanceBefore: inv.previousBalance + inv.totalSum,
          type: 'sale_payment',
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber.toString(),
          timestamp: inv.date,
        );
        upsertLocal(payHist);
        list.add(payHist);
      } else if (inv.paidAmount > 0) {
        final payEntry = paymentEntries.first;
        if ((payEntry.enteredBalance - inv.paidAmount).abs() > 0.001) {
          payEntry.enteredBalance = inv.paidAmount;
          upsertLocal(payEntry);
        }
      } else if (paymentEntries.isNotEmpty) {
        final keysToDelete =
            paymentEntries.map((e) => _boxKey(e.parentType, e.parentId, e.id));
        balanceHistoryBox.deleteAll(keysToDelete);
        list.removeWhere(
          (e) => e.type == 'sale_payment' && matchesInvoice(e, invId, invNum),
        );
      }
    }

    // Auto-populate missing history entries for active local return invoices in Hive
    for (final ret in activeReturns) {
      final retId = ret.id.trim();
      final retNum = ret.invoiceNumber.toString().trim();
      final returnEntries = list
          .where(
            (e) => e.type == 'return' && matchesInvoice(e, retId, retNum),
          )
          .toList();
      final returnPaymentEntries = list
          .where(
            (e) =>
                e.type == 'return_payment' && matchesInvoice(e, retId, retNum),
          )
          .toList();

      if (returnEntries.isEmpty) {
        final returnHist = BalanceHistoryLocal(
          id: '${ret.id}_return',
          parentId: cId,
          parentType: 'client',
          enteredBalance: ret.totalSum,
          balanceBefore: ret.previousBalance,
          type: 'return',
          invoiceId: ret.id,
          invoiceNumber: ret.invoiceNumber.toString(),
          timestamp: ret.date,
        );
        upsertLocal(returnHist);
        list.add(returnHist);
      } else {
        final returnEntry = returnEntries.first;
        if ((returnEntry.enteredBalance - ret.totalSum).abs() > 0.001) {
          returnEntry.enteredBalance = ret.totalSum;
          upsertLocal(returnEntry);
        }
      }

      if (ret.paidAmount > 0 && returnPaymentEntries.isEmpty) {
        final payHist = BalanceHistoryLocal(
          id: '${ret.id}_return_pay',
          parentId: cId,
          parentType: 'client',
          enteredBalance: ret.paidAmount,
          balanceBefore: ret.previousBalance - ret.totalSum,
          type: 'return_payment',
          invoiceId: ret.id,
          invoiceNumber: ret.invoiceNumber.toString(),
          timestamp: ret.date,
        );
        upsertLocal(payHist);
        list.add(payHist);
      } else if (ret.paidAmount > 0) {
        final payEntry = returnPaymentEntries.first;
        if ((payEntry.enteredBalance - ret.paidAmount).abs() > 0.001) {
          payEntry.enteredBalance = ret.paidAmount;
          upsertLocal(payEntry);
        }
      } else if (returnPaymentEntries.isNotEmpty) {
        final keysToDelete = returnPaymentEntries
            .map((e) => _boxKey(e.parentType, e.parentId, e.id));
        balanceHistoryBox.deleteAll(keysToDelete);
        list.removeWhere(
          (e) => e.type == 'return_payment' && matchesInvoice(e, retId, retNum),
        );
      }
    }

    list.sort(_compareHistoryAscending);

    bool isInvoiceActive(BalanceHistoryLocal item) {
      final type = item.type;
      if (type == 'sale' || type == 'sale_payment') {
        if (activeSales.isEmpty) return false;
        final itemInvId = item.invoiceId.trim();
        final itemInvNum = item.invoiceNumber.trim();
        final itemId = item.id.trim();
        return activeSales.any((inv) {
          final invId = inv.id.trim();
          final invNum = inv.invoiceNumber.toString().trim();
          if (invId.isNotEmpty &&
              (invId == itemInvId ||
                  invId == itemId ||
                  itemId.startsWith(invId) ||
                  itemInvId.startsWith(invId))) {
            return type != 'sale_payment' || inv.paidAmount > 0;
          }
          if (invNum.isNotEmpty &&
              (invNum == itemInvNum ||
                  itemInvNum == invNum ||
                  itemId.contains(invNum))) {
            return type != 'sale_payment' || inv.paidAmount > 0;
          }
          return false;
        });
      } else if (type == 'return' || type == 'return_payment') {
        if (activeReturns.isEmpty) return false;
        final itemInvId = item.invoiceId.trim();
        final itemInvNum = item.invoiceNumber.trim();
        final itemId = item.id.trim();
        return activeReturns.any((inv) {
          final invId = inv.id.trim();
          final invNum = inv.invoiceNumber.toString().trim();
          if (invId.isNotEmpty &&
              (invId == itemInvId ||
                  invId == itemId ||
                  itemId.startsWith(invId) ||
                  itemInvId.startsWith(invId))) {
            return type != 'return_payment' || inv.paidAmount > 0;
          }
          if (invNum.isNotEmpty &&
              (invNum == itemInvNum ||
                  itemInvNum == invNum ||
                  itemId.contains(invNum))) {
            return type != 'return_payment' || inv.paidAmount > 0;
          }
          return false;
        });
      }
      return true;
    }

    final seenKeys = <String>{};
    final deduplicated = <BalanceHistoryLocal>[];
    final keysToPurge = <String>[];

    for (final item in list) {
      if (!isInvoiceActive(item)) {
        keysToPurge.add(_boxKey(item.parentType, item.parentId, item.id));
        continue;
      }
      // Invoice numbers are stable across legacy root/subcollection IDs. Use
      // them first so the same invoice is shown only once even when older sync
      // code saved the two history rows with different invoice IDs.
      final key = item.invoiceNumber.isNotEmpty
          ? '${item.invoiceNumber}_${item.type}'
          : (item.invoiceId.isNotEmpty
              ? '${item.invoiceId}_${item.type}'
              : item.id);
      if (seenKeys.add(key)) {
        deduplicated.add(item);
      }
    }

    if (keysToPurge.isNotEmpty) {
      balanceHistoryBox.deleteAll(keysToPurge);
    }

    return deduplicated;
  }

  List<BalanceHistoryLocal> getForSupplier(String supplierId) {
    final sId = supplierId.trim();
    final list = balanceHistoryBox.values
        .where((e) => e.parentType == 'supplier' && e.parentId == sId)
        .toList();

    final activeBuying = InvoiceRepository.instance.getBuyingBySupplier(sId);

    bool matchesInvoice(
      BalanceHistoryLocal entry,
      String invoiceId,
      String invoiceNumber,
    ) {
      return (invoiceId.isNotEmpty &&
              (entry.invoiceId == invoiceId ||
                  entry.id == invoiceId ||
                  entry.id.startsWith(invoiceId))) ||
          (invoiceNumber.isNotEmpty &&
              (entry.invoiceNumber == invoiceNumber ||
                  entry.id.contains(invoiceNumber)));
    }

    // Keep the local supplier ledger usable immediately while Firestore sync
    // runs in the background. A purchase and its payment are separate effects.
    for (final inv in activeBuying) {
      final invId = inv.id.trim();
      final invNum = inv.invoiceNumber.toString().trim();
      final buyingEntries = list
          .where(
            (e) => e.type == 'buying' && matchesInvoice(e, invId, invNum),
          )
          .toList();
      final paymentEntries = list
          .where(
            (e) =>
                e.type == 'buying_payment' && matchesInvoice(e, invId, invNum),
          )
          .toList();

      if (buyingEntries.isEmpty) {
        final buyingEntry = BalanceHistoryLocal(
          id: '${inv.id}_buying',
          parentId: sId,
          parentType: 'supplier',
          enteredBalance: inv.totalSum,
          balanceBefore: inv.previousBalance,
          type: 'buying',
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber.toString(),
          timestamp: inv.date,
        );
        upsertLocal(buyingEntry);
        list.add(buyingEntry);
      } else {
        // Repair entries written by older builds, which stored paidAmount as
        // the purchase amount and therefore understated supplier balances.
        final buyingEntry = buyingEntries.first;
        if ((buyingEntry.enteredBalance - inv.totalSum).abs() > 0.001) {
          buyingEntry.enteredBalance = inv.totalSum;
          upsertLocal(buyingEntry);
        }
      }

      if (inv.paidAmount > 0 && paymentEntries.isEmpty) {
        final paymentEntry = BalanceHistoryLocal(
          id: '${inv.id}_pay',
          parentId: sId,
          parentType: 'supplier',
          enteredBalance: inv.paidAmount,
          balanceBefore: inv.previousBalance + inv.totalSum,
          type: 'buying_payment',
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber.toString(),
          timestamp: inv.date,
        );
        upsertLocal(paymentEntry);
        list.add(paymentEntry);
      } else if (inv.paidAmount > 0) {
        final paymentEntry = paymentEntries.first;
        if ((paymentEntry.enteredBalance - inv.paidAmount).abs() > 0.001) {
          paymentEntry.enteredBalance = inv.paidAmount;
          upsertLocal(paymentEntry);
        }
      }
    }

    bool isActiveInvoiceEntry(BalanceHistoryLocal item) {
      if (item.type != 'buying' && item.type != 'buying_payment') return true;
      if (activeBuying.isEmpty) return true;
      for (final inv in activeBuying) {
        if (!matchesInvoice(
          item,
          inv.id.trim(),
          inv.invoiceNumber.toString().trim(),
        )) {
          continue;
        }
        return item.type != 'buying_payment' || inv.paidAmount > 0;
      }
      return false;
    }

    // Preserve old cache records for audit/recovery, but exclude orphaned or
    // obsolete invoice effects from display and balance calculations.
    list.removeWhere((item) => !isActiveInvoiceEntry(item));
    list.sort(_compareHistoryAscending);

    // Invoice numbers survive legacy root/subcollection ID mismatches.
    final seenKeys = <String>{};
    final deduplicated = <BalanceHistoryLocal>[];
    for (final item in list) {
      final key = item.invoiceNumber.isNotEmpty
          ? '${item.invoiceNumber}_${item.type}'
          : (item.invoiceId.isNotEmpty
              ? '${item.invoiceId}_${item.type}'
              : item.id);
      if (seenKeys.add(key)) {
        deduplicated.add(item);
      }
    }
    return deduplicated;
  }

  /// Calculates the supplier balance from the same deduplicated ledger shown
  /// in supplier history. The cached balance is only a pre-sync fallback.
  double calculateSupplierBalance(
    String supplierId, {
    double fallback = 0.0,
  }) {
    final history = getForSupplier(supplierId);
    if (history.isEmpty) return fallback;

    var running = 0.0;
    for (final entry in history) {
      final type = entry.type;
      final direction = entry.direction.trim();
      final isIncrease = type == 'buying' ||
          type == 'addition' ||
          (type == 'opening' && direction != '\u0639\u0644\u064a\u0647') ||
          (type == 'voucher' && direction == '\u0644\u0647');
      running += isIncrease ? entry.enteredBalance : -entry.enteredBalance;
    }
    return running;
  }

  /// Calculates the client balance from the same deduplicated ledger shown in
  /// balance history. The cached client balance is used only when no ledger is
  /// available yet (for example, before the first data sync).
  double calculateClientBalance(
    String clientId, {
    double fallback = 0.0,
  }) {
    final history = getForClient(clientId);
    if (history.isEmpty) return fallback;

    var running = 0.0;
    for (final entry in history) {
      final isIncrease = entry.type == 'sale' ||
          entry.type == 'addition' ||
          entry.type == 'opening' ||
          entry.type == 'return_payment';
      running += isIncrease ? entry.enteredBalance : -entry.enteredBalance;
    }
    return running;
  }

  Future<void> upsertLocal(BalanceHistoryLocal entry) async {
    final key = _boxKey(entry.parentType, entry.parentId, entry.id);
    await balanceHistoryBox.put(key, entry);
  }

  Future<void> deleteLocal(
      String parentType, String parentId, String docId) async {
    final key = _boxKey(parentType, parentId, docId);
    await balanceHistoryBox.delete(key);
  }

  Future<void> deleteByInvoiceId(
    String parentType,
    String parentId,
    String invoiceId, {
    String? invoiceNumber,
  }) async {
    final invId = invoiceId.trim();
    final invNum = (invoiceNumber ?? '').trim();

    final keysToDelete = balanceHistoryBox.values
        .where((e) {
          if (e.parentType != parentType || e.parentId != parentId)
            return false;
          if (invId.isNotEmpty &&
              (e.invoiceId == invId ||
                  e.id == invId ||
                  e.id == '${invId}_sale' ||
                  e.id == '${invId}_pay' ||
                  e.id == '${invId}_return' ||
                  e.id == '${invId}_return_pay' ||
                  e.id.startsWith(invId) ||
                  e.invoiceId.startsWith(invId))) {
            return true;
          }
          if (invNum.isNotEmpty &&
              (e.invoiceNumber == invNum ||
                  e.id.contains(invNum) ||
                  e.invoiceId.contains(invNum))) {
            return true;
          }
          return false;
        })
        .map((e) => _boxKey(e.parentType, e.parentId, e.id))
        .toList();
    await balanceHistoryBox.deleteAll(keysToDelete);
  }

  Future<void> deleteForParent(String parentType, String parentId) async {
    final keysToDelete = balanceHistoryBox.values
        .where((e) => e.parentType == parentType && e.parentId == parentId)
        .map((e) => _boxKey(e.parentType, e.parentId, e.id))
        .toList();
    await balanceHistoryBox.deleteAll(keysToDelete);
  }

  Future<void> fullSyncForClient(String clientId) async {
    final snap = await _fs
        .collection('clients')
        .doc(clientId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs) {
      final entry = BalanceHistoryLocal.fromFirestore(
        doc.id,
        clientId,
        'client',
        doc.data(),
      );
      await upsertLocal(entry);
    }
  }

  Future<void> fullSyncForSupplier(String supplierId) async {
    final snap = await _fs
        .collection('suppliers')
        .doc(supplierId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs) {
      final entry = BalanceHistoryLocal.fromFirestore(
        doc.id,
        supplierId,
        'supplier',
        doc.data(),
      );
      await upsertLocal(entry);
    }
  }
}
