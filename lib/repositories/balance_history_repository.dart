import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';
import 'invoice_repository.dart';
import '../Services/customer_balance_store.dart';
import '../Services/supplier_balance_store.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/local_operation_journal.dart';

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
      case 'buying_return':
        return 3;
      case 'return_payment':
      case 'buying_return_payment':
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

  /// Pure compatibility view. Unmatched history is retained, never purged.
  List<BalanceHistoryLocal> getForClient(String clientId) {
    final cId = clientId.trim();
    final name = clientsBox.get(cId)?.name;
    final sales =
        InvoiceRepository.instance.getSalesByClient(cId, clientName: name);
    final returns =
        InvoiceRepository.instance.getReturnsByClient(cId, clientName: name);
    final raw = balanceHistoryBox.values
        .where((e) => e.parentType == 'client' && e.parentId == cId)
        .toList();
    final result = <BalanceHistoryLocal>[];
    for (final entry in raw) {
      final isSale = entry.type == 'sale' || entry.type == 'sale_payment';
      final isReturn = entry.type == 'return' || entry.type == 'return_payment';
      if (!isSale && !isReturn) {
        result.add(entry);
        continue;
      }
      final collection = isReturn ? 'returnInvoices' : 'invoices';
      if (entry.invoiceId.isNotEmpty &&
          appMetaBox.get('deletedCustomerInvoice:' +
                  collection +
                  ':' +
                  entry.invoiceId) ==
              true) continue;
      final invoices = isReturn ? returns : sales;
      final linkedId = appMetaBox
              .get('customerInvoiceAlias:' + collection + ':' + entry.invoiceId)
              ?.toString() ??
          entry.invoiceId;
      final exact = invoices.any((inv) =>
          linkedId == inv.id ||
          entry.id == inv.id ||
          entry.id == inv.id + '_sale' ||
          entry.id == inv.id + '_pay' ||
          entry.id == inv.id + '_return' ||
          entry.id == inv.id + '_return_pay');
      if (exact) continue;
      result.add(entry);
    }
    void addInvoice(dynamic inv, bool isReturn) {
      result.add(BalanceHistoryLocal(
          id: inv.id + (isReturn ? '_return' : '_sale'),
          parentId: cId,
          parentType: 'client',
          enteredBalance: inv.totalSum,
          balanceBefore: inv.previousBalance,
          type: isReturn ? 'return' : 'sale',
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber.toString(),
          timestamp: inv.date));
      if (inv.paidAmount > 0)
        result.add(BalanceHistoryLocal(
            id: inv.id + (isReturn ? '_return_pay' : '_pay'),
            parentId: cId,
            parentType: 'client',
            enteredBalance: inv.paidAmount,
            balanceBefore:
                inv.previousBalance + (isReturn ? -inv.totalSum : inv.totalSum),
            type: isReturn ? 'return_payment' : 'sale_payment',
            invoiceId: inv.id,
            invoiceNumber: inv.invoiceNumber.toString(),
            timestamp: inv.date));
    }

    for (final invoice in sales) {
      addInvoice(invoice, false);
    }
    for (final invoice in returns) {
      addInvoice(invoice, true);
    }
    result.sort(_compareHistoryAscending);
    return result;
  }

  List<BalanceHistoryLocal> getForSupplier(String supplierId) {
    final sId = supplierId.trim();
    final raw = balanceHistoryBox.values
        .where((e) => e.parentType == 'supplier' && e.parentId == sId)
        .toList();
    final activeBuying = InvoiceRepository.instance.getBuyingBySupplier(sId);
    final activeBuyingReturns =
        InvoiceRepository.instance.getBuyingReturnsBySupplier(sId);
    final result = <BalanceHistoryLocal>[];

    bool belongsTo(dynamic invoice, BalanceHistoryLocal entry) {
      final id = invoice.id.toString().trim();
      return id.isNotEmpty &&
          (entry.invoiceId.trim() == id ||
              entry.id == id ||
              entry.id == '${id}_buying' ||
              entry.id == '${id}_pay' ||
              entry.id == '${id}_buying_return' ||
              entry.id == '${id}_buying_return_pay');
    }

    // Invoice rows are projected from the cached invoices below. Retain every
    // unrelated legacy/manual row without changing Hive during a read.
    for (final entry in raw) {
      final isBuying = entry.type == 'buying' || entry.type == 'buying_payment';
      final isReturn = entry.type == 'buying_return' ||
          entry.type == 'buying_return_payment' ||
          entry.type == 'return' ||
          entry.type == 'return_payment';
      final matched = isBuying
          ? activeBuying.any((invoice) => belongsTo(invoice, entry))
          : isReturn
              ? activeBuyingReturns.any((invoice) => belongsTo(invoice, entry))
              : false;
      if (!matched) result.add(entry);
    }

    void addInvoice(dynamic invoice, bool isReturn) {
      result.add(BalanceHistoryLocal(
        id: '${invoice.id}_${isReturn ? 'buying_return' : 'buying'}',
        parentId: sId,
        parentType: 'supplier',
        enteredBalance: invoice.totalSum,
        balanceBefore: invoice.previousBalance,
        type: isReturn ? 'buying_return' : 'buying',
        invoiceId: invoice.id,
        invoiceNumber: invoice.invoiceNumber.toString(),
        timestamp: invoice.date,
      ));
      if (invoice.paidAmount > 0) {
        result.add(BalanceHistoryLocal(
          id: '${invoice.id}_${isReturn ? 'buying_return_pay' : 'pay'}',
          parentId: sId,
          parentType: 'supplier',
          enteredBalance: invoice.paidAmount,
          balanceBefore: invoice.previousBalance +
              (isReturn ? -invoice.totalSum : invoice.totalSum),
          type: isReturn ? 'buying_return_payment' : 'buying_payment',
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber.toString(),
          timestamp: invoice.date,
        ));
      }
    }

    for (final invoice in activeBuying) {
      addInvoice(invoice, false);
    }
    for (final invoice in activeBuyingReturns) {
      addInvoice(invoice, true);
    }
    result.sort(_compareHistoryAscending);
    return result;
  }

  /// Calculates the supplier balance from the same deduplicated ledger shown
  /// in supplier history. The cached balance is only a pre-sync fallback.
  double calculateSupplierBalance(
    String supplierId, {
    double fallback = 0.0,
  }) {
    if (SupplierBalanceStore.hasBase(supplierId)) {
      return SupplierBalanceStore.balance(supplierId, fallback: fallback);
    }
    final history = getForSupplier(supplierId);
    if (history.isEmpty) return fallback;

    var running = 0.0;
    for (final entry in history) {
      final type = entry.type;
      final direction = entry.direction.trim();
      final isIncrease = type == 'buying' ||
          type == 'addition' ||
          type == 'buying_return_payment' ||
          type == 'return_payment' ||
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
    if (CustomerBalanceStore.hasBase(clientId))
      return CustomerBalanceStore.balance(clientId);
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

  Future<void> mergeCloudClientHistory(
          String clientId, String historyId, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'clients/' + clientId + '/balanceHistory/' + historyId;
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (data == null || data['_deleted'] == true) {
          await deleteLocal('client', clientId, historyId);
        } else {
          await upsertLocal(BalanceHistoryLocal.fromFirestore(
              historyId, clientId, 'client', data));
        }
        if (data != null) await CloudSnapshotGuard.record(path, data);
      });
  Future<void> fullSyncForClient(String clientId) async {
    final snap = await _fs
        .collection('clients')
        .doc(clientId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs)
      await mergeCloudClientHistory(clientId, doc.id, doc.data());
  }

  Future<void> fullSyncForSupplier(String supplierId) async {
    final snap = await _fs
        .collection('suppliers')
        .doc(supplierId)
        .collection('balanceHistory')
        .get();
    for (final doc in snap.docs) {
      await mergeCloudSupplierHistory(supplierId, doc.id, doc.data());
    }
  }

  Future<void> mergeCloudSupplierHistory(
          String supplierId, String historyId, Map<String, dynamic>? data) =>
      LocalOperationJournal.exclusive(() async {
        final path = 'suppliers/$supplierId/balanceHistory/$historyId';
        if (!CloudSnapshotGuard.accepts(path, data)) return;
        if (data == null || data['_deleted'] == true) {
          await deleteLocal('supplier', supplierId, historyId);
        } else {
          await upsertLocal(BalanceHistoryLocal.fromFirestore(
              historyId, supplierId, 'supplier', data));
        }
        if (data != null) await CloudSnapshotGuard.record(path, data);
      });
}
