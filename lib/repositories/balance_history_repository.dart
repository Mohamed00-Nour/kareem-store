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
      final hasSaleEntry = list.any(
        (e) => e.type == 'sale' && matchesInvoice(e, invId, invNum),
      );
      final hasPaymentEntry = list.any(
        (e) => e.type == 'sale_payment' && matchesInvoice(e, invId, invNum),
      );

      if (!hasSaleEntry) {
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
      }

      if (inv.paidAmount > 0 && !hasPaymentEntry) {
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
      }
    }

    // Auto-populate missing history entries for active local return invoices in Hive
    for (final ret in activeReturns) {
      final retId = ret.id.trim();
      final retNum = ret.invoiceNumber.toString().trim();
      final hasReturnEntry = list.any(
        (e) => e.type == 'return' && matchesInvoice(e, retId, retNum),
      );
      final hasReturnPaymentEntry = list.any(
        (e) => e.type == 'return_payment' && matchesInvoice(e, retId, retNum),
      );

      if (!hasReturnEntry) {
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
      }

      if (ret.paidAmount > 0 && !hasReturnPaymentEntry) {
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
      }
    }

    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

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
          if (invId.isNotEmpty && (invId == itemInvId || invId == itemId || itemId.startsWith(invId) || itemInvId.startsWith(invId))) {
            return true;
          }
          if (invNum.isNotEmpty && (invNum == itemInvNum || itemInvNum == invNum || itemId.contains(invNum))) {
            return true;
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
          if (invId.isNotEmpty && (invId == itemInvId || invId == itemId || itemId.startsWith(invId) || itemInvId.startsWith(invId))) {
            return true;
          }
          if (invNum.isNotEmpty && (invNum == itemInvNum || itemInvNum == invNum || itemId.contains(invNum))) {
            return true;
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
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Deduplicate by entry ID or invoiceId + type
    final seenKeys = <String>{};
    final deduplicated = <BalanceHistoryLocal>[];
    for (final item in list) {
      final key = item.invoiceId.isNotEmpty
          ? '${item.invoiceId}_${item.type}'
          : item.id;
      if (seenKeys.add(key)) {
        deduplicated.add(item);
      }
    }
    return deduplicated;
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

  Future<void> deleteLocal(String parentType, String parentId, String docId) async {
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
          if (e.parentType != parentType || e.parentId != parentId) return false;
          if (invId.isNotEmpty && (
              e.invoiceId == invId ||
              e.id == invId ||
              e.id == '${invId}_sale' ||
              e.id == '${invId}_pay' ||
              e.id == '${invId}_return' ||
              e.id == '${invId}_return_pay' ||
              e.id.startsWith(invId) ||
              e.invoiceId.startsWith(invId))) {
            return true;
          }
          if (invNum.isNotEmpty && (
              e.invoiceNumber == invNum ||
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
