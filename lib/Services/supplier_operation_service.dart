import 'package:uuid/uuid.dart';

import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/financial_cloud_store.dart';
import '../sync/local_operation_journal.dart';
import 'invoice_number_utils.dart';
import 'supplier_balance_store.dart';

/// Durable local-first operations for purchases and supplier payments.
class SupplierOperationService {
  static const _uuid = Uuid();

  static Map<String, dynamic> supplierMap(String id) {
    final supplier = suppliersBox.get(id);
    if (supplier == null) {
      throw StateError('Supplier is not available locally: $id');
    }
    return {
      'id': id,
      'supplierName': supplier.name,
      'name': supplier.name,
      'balance': supplier.balance,
      'totalBalance': supplier.balance,
      'phone': supplier.phone,
      'address': supplier.address,
    };
  }

  static Future<String> createSupplier({
    required String name,
    required double openingBalance,
    String phone = '',
    String address = '',
  }) async {
    final supplierId = _uuid.v4();
    await LocalOperationJournal.commit((operationId) async {
      if (SupplierRepository.instance.findByName(name) != null) {
        throw StateError('Supplier already exists');
      }
      final data = {
        'id': supplierId,
        'name': name,
        'supplierName': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
        'balance': 0.0,
        'totalBalance': 0.0,
      };
      final createdAt = DateTime.now();
      final openingHistoryId = '${supplierId}_opening';
      final openingVoucherId = '${supplierId}_opening';
      final plan = _SupplierPlan(operationId, 'createSupplier', 'إنشاء مورد');
      plan.local(
          HiveBoxNames.appMeta, SupplierBalanceStore.baseKey(supplierId), 0.0);
      plan.cloud('suppliers/$supplierId', data: data, absent: true);
      plan.supplier(supplierId, openingBalance, initial: data);
      if (openingBalance != 0) {
        plan.history(BalanceHistoryLocal(
          id: openingHistoryId,
          parentId: supplierId,
          parentType: 'supplier',
          enteredBalance: openingBalance,
          type: 'opening',
          direction: 'له',
          notes: 'رصيد افتتاحي',
          timestamp: createdAt,
        ));
        final voucher = {
          'id': openingVoucherId,
          'voucherId': openingVoucherId,
          'historyId': openingHistoryId,
          'supplierId': supplierId,
          'supplierName': name,
          'direction': 'له',
          'amount': openingBalance,
          'description': 'رصيد افتتاحي',
          'date': createdAt,
          'timestamp': createdAt,
        };
        plan.local(
            HiveBoxNames.appMeta, 'supplierVoucher:$openingVoucherId', voucher);
        plan.cloud('supplier_vouchers/$openingVoucherId',
            data: voucher, absent: true);
      }
      return plan.finish({
        'supplierId': supplierId,
        'openingBalance': openingBalance,
        'openingHistoryId': openingHistoryId,
        'openingVoucherId': openingVoucherId,
        'createdAt': createdAt,
      });
    });
    return supplierId;
  }

  static Future<Map<String, dynamic>> saveBuyingInvoice(
    Map<String, dynamic> input, {
    bool editing = false,
  }) async {
    late Map<String, dynamic> saved;
    await LocalOperationJournal.commit((operationId) async {
      final invoiceId = input['id']?.toString().isNotEmpty == true
          ? input['id'].toString()
          : _uuid.v4();
      final old = buyingInvoicesBox.get(invoiceId);
      if (editing && old == null) {
        throw StateError('Purchase invoice must be cached before editing');
      }
      if (!editing && old != null) {
        throw StateError('Purchase invoice already exists');
      }
      final supplierId = input['supplierId']?.toString() ?? '';
      if (supplierId.isEmpty || suppliersBox.get(supplierId) == null) {
        throw StateError('Supplier must be cached before saving');
      }
      final total = _amount(input['totalSum'], 'totalSum');
      final paid = _amount(input['paidAmount'], 'paidAmount');
      final oldData = old?.toMap();
      final oldSupplierId = old?.supplierId ?? supplierId;
      final oldEffect = old == null ? 0.0 : old.totalSum - old.paidAmount;
      final newEffect = total - paid;
      final date = _date(input['date']);
      final lines = _lines(input['products']);
      final data = <String, dynamic>{
        ...input,
        'id': invoiceId,
        'invoiceId': invoiceId,
        'supplierId': supplierId,
        'supplierName': suppliersBox.get(supplierId)!.name,
        'date': date,
        'totalSum': total,
        'paidAmount': paid,
        'balance': newEffect,
        'invoiceType': 'buying',
        'products': lines,
      };
      final plan = _SupplierPlan(
          operationId,
          editing ? 'editBuyingInvoice' : 'createBuyingInvoice',
          editing ? 'تعديل فاتورة مشتريات' : 'فاتورة مشتريات');
      plan.local(HiveBoxNames.buyingInvoices, invoiceId, data);
      plan.cloud('buying invoices/$invoiceId',
          data: data, absent: !editing, expected: oldData);
      if (editing && oldSupplierId != supplierId) {
        plan.cloud('suppliers/$oldSupplierId/buying invoices/$invoiceId',
            deleted: true, expected: oldData);
        plan.removeInvoiceHistory(oldSupplierId, invoiceId);
        plan.supplier(oldSupplierId, -oldEffect);
        plan.supplier(supplierId, newEffect);
      } else {
        plan.supplier(supplierId, newEffect - oldEffect);
        if (editing) plan.removeInvoiceHistory(supplierId, invoiceId);
      }
      plan.cloud('suppliers/$supplierId/buying invoices/$invoiceId',
          data: data,
          absent: !editing || oldSupplierId != supplierId,
          expected: editing && oldSupplierId == supplierId ? oldData : null);
      plan.invoiceHistory(supplierId, data);
      plan.stockDifference(
          old?.products ?? const [], lines, date, data['invoiceNumber']);
      plan.cash(-(paid - (old?.paidAmount ?? 0)),
          editing ? 'تعديل فاتورة مشتريات' : 'فاتورة مشتريات',
          date: date);
      saved = data;
      return plan.finish({
        'supplierId': supplierId,
        'invoiceId': invoiceId,
        'invoiceData': data,
      });
    });
    return saved;
  }

  static Future<void> deleteBuyingInvoice(String invoiceId) async {
    await LocalOperationJournal.commit((operationId) async {
      final old = buyingInvoicesBox.get(invoiceId);
      if (old == null) {
        throw StateError('Purchase invoice must be cached before deleting');
      }
      final supplierId = old.supplierId;
      if (supplierId.isEmpty || suppliersBox.get(supplierId) == null) {
        throw StateError('Supplier must be cached before deleting purchase');
      }
      final oldData = old.toMap();
      final plan = _SupplierPlan(
          operationId, 'deleteBuyingInvoice', 'حذف فاتورة مشتريات');
      plan.local(HiveBoxNames.buyingInvoices, invoiceId, null);
      plan.cloud('buying invoices/$invoiceId',
          deleted: true, expected: oldData);
      plan.cloud('suppliers/$supplierId/buying invoices/$invoiceId',
          deleted: true, expected: oldData);
      plan.removeInvoiceHistory(supplierId, invoiceId);
      plan.supplier(supplierId, -(old.totalSum - old.paidAmount));
      plan.stockDifference(
          old.products, const [], DateTime.now(), old.invoiceNumber);
      plan.cash(old.paidAmount, 'حذف فاتورة مشتريات');
      return plan.finish({
        'supplierId': supplierId,
        'supplierName': old.supplierName,
        'invoiceId': invoiceId,
        'invoiceNumber': old.invoiceNumber,
        'totalSum': old.totalSum,
      });
    });
  }

  static Future<SupplierPaymentResultData> savePayment({
    required String supplierId,
    required String direction,
    required double amount,
    required String description,
    required DateTime date,
    required String paymentMethod,
    required int voucherNumber,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount');
    }
    if (direction != 'عليه' && direction != 'له') {
      throw ArgumentError.value(direction, 'direction');
    }
    late SupplierPaymentResultData result;
    await LocalOperationJournal.commit((operationId) async {
      final supplier = suppliersBox.get(supplierId);
      if (supplier == null) throw StateError('Supplier is not cached');
      final before =
          SupplierBalanceStore.balance(supplierId, fallback: supplier.balance);
      final delta = direction == 'له' ? amount : -amount;
      final historyId = 'supplier_voucher_$operationId';
      final voucherId = '${historyId}_voucher';
      final notes = [
        'سند $direction رقم $voucherNumber',
        if (description.trim().isNotEmpty) description.trim(),
      ].join(' - ');
      final history = BalanceHistoryLocal(
        id: historyId,
        parentId: supplierId,
        parentType: 'supplier',
        enteredBalance: amount,
        balanceBefore: before,
        type: 'voucher',
        direction: direction,
        notes: notes,
        timestamp: date,
      );
      final voucher = {
        'id': voucherId,
        'voucherId': voucherId,
        'historyId': historyId,
        'supplierId': supplierId,
        'supplierName': supplier.name,
        'voucherNumber': voucherNumber,
        'direction': direction,
        'amount': amount,
        'description': description.trim(),
        'paymentMethod': paymentMethod,
        'date': date,
      };
      final plan = _SupplierPlan(
          operationId, 'adjustSupplierBalance', 'سند مورد $direction');
      plan.supplier(supplierId, delta);
      plan.history(history);
      plan.local(HiveBoxNames.appMeta, 'supplierVoucher:$voucherId', voucher);
      plan.cloud('supplier_vouchers/$voucherId', data: voucher, absent: true);
      if (direction == 'عليه') {
        plan.cash(-amount, 'سند مورد $direction', date: date);
      }
      result = SupplierPaymentResultData(
          previousBalance: before,
          newBalance: before + delta,
          historyId: historyId);
      return plan.finish({
        'supplierId': supplierId,
        'historyId': historyId,
        'voucherId': voucherId,
        'voucherNumber': voucherNumber,
        'direction': direction,
        'paymentMethod': paymentMethod,
      });
    });
    return result;
  }

  static double _amount(dynamic value, String name) {
    final parsed = invoiceTryParseAmount(value);
    if (parsed == null || parsed < 0) {
      throw ArgumentError('Invalid $name');
    }
    return parsed;
  }

  static DateTime _date(dynamic value) => value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  static List<Map<String, dynamic>> _lines(dynamic value) =>
      (value as List? ?? const [])
          .map((line) => Map<String, dynamic>.from(line as Map))
          .toList();
}

class SupplierPaymentResultData {
  final double previousBalance;
  final double newBalance;
  final String historyId;
  const SupplierPaymentResultData(
      {required this.previousBalance,
      required this.newBalance,
      required this.historyId});
}

class _SupplierPlan {
  final String id, operationType, description;
  final localWrites = <Map<String, dynamic>>[];
  final cloudWrites = <String, Map<String, dynamic>>{};
  final supplierDeltas = <String, double>{};

  _SupplierPlan(this.id, this.operationType, this.description);

  void local(String box, String key, dynamic data) {
    localWrites.removeWhere((item) => item['box'] == box && item['key'] == key);
    localWrites.add({'box': box, 'key': key, 'data': data});
  }

  void cloud(String path,
      {Map<String, dynamic>? data,
      Map<String, dynamic>? increments,
      bool absent = false,
      bool deleted = false,
      Map<String, dynamic>? expected}) {
    final write = <String, dynamic>{
      'path': path,
      'data': data ?? {},
      'increments': increments ?? {},
      'deleted': deleted,
      'mustBeAbsent': absent,
    };
    if (expected != null) {
      write['expectedOperationId'] = appMetaBox
          .get(CloudSnapshotGuard.operationKey(path), defaultValue: '');
      if (expected.containsKey('products')) {
        write['expectedFinancialState'] = financialInvoiceState(expected);
      }
      write['expectedFields'] = {
        for (final key in ['totalSum', 'paidAmount', 'enteredBalance'])
          if (expected.containsKey(key)) key: expected[key]
      };
    }
    cloudWrites[path] = write;
    local(HiveBoxNames.appMeta, CloudSnapshotGuard.operationKey(path), id);
  }

  void supplier(String supplierId, double delta,
      {Map<String, dynamic>? initial}) {
    final data = initial ?? SupplierOperationService.supplierMap(supplierId);
    if (!SupplierBalanceStore.hasBase(supplierId) && initial == null) {
      local(HiveBoxNames.appMeta, SupplierBalanceStore.baseKey(supplierId),
          invoiceNum(data['totalBalance'] ?? data['balance']));
    }
    supplierDeltas[supplierId] = (supplierDeltas[supplierId] ?? 0) + delta;
    final totalDelta = supplierDeltas[supplierId]!;
    final before = initial == null
        ? SupplierBalanceStore.balance(supplierId,
            fallback: invoiceNum(data['totalBalance'] ?? data['balance']))
        : 0.0;
    local(HiveBoxNames.appMeta, SupplierBalanceStore.eventKey(supplierId, id), {
      'delta': totalDelta,
      'operationId': id,
      'timestamp': DateTime.now(),
      'description': description,
    });
    local(HiveBoxNames.suppliers, supplierId, {
      ...data,
      'balance': before + totalDelta,
      'totalBalance': before + totalDelta,
    });
  }

  void history(BalanceHistoryLocal entry) {
    local(
        HiveBoxNames.balanceHistory, 'supplier_${entry.parentId}_${entry.id}', {
      ...entry.toMap(),
      'parentId': entry.parentId,
      'parentType': 'supplier',
    });
    cloud('suppliers/${entry.parentId}/balanceHistory/${entry.id}',
        data: entry.toMap());
  }

  void invoiceHistory(String supplierId, Map<String, dynamic> data) {
    final invoiceId = data['id'].toString();
    final total = invoiceNum(data['totalSum']);
    final paid = invoiceNum(data['paidAmount']);
    final date = SupplierOperationService._date(data['date']);
    history(BalanceHistoryLocal(
      id: '${invoiceId}_buying',
      parentId: supplierId,
      parentType: 'supplier',
      enteredBalance: total,
      type: 'buying',
      invoiceId: invoiceId,
      invoiceNumber: data['invoiceNumber'].toString(),
      timestamp: date,
    ));
    if (paid > 0) {
      history(BalanceHistoryLocal(
        id: '${invoiceId}_pay',
        parentId: supplierId,
        parentType: 'supplier',
        enteredBalance: paid,
        type: 'buying_payment',
        invoiceId: invoiceId,
        invoiceNumber: data['invoiceNumber'].toString(),
        timestamp: date,
      ));
    }
  }

  void removeInvoiceHistory(String supplierId, String invoiceId) {
    for (final entry in balanceHistoryBox.values
        .where((entry) =>
            entry.parentType == 'supplier' &&
            entry.parentId == supplierId &&
            (entry.invoiceId == invoiceId ||
                entry.id == '${invoiceId}_buying' ||
                entry.id == '${invoiceId}_pay'))
        .toList()) {
      local(HiveBoxNames.balanceHistory, 'supplier_${supplierId}_${entry.id}',
          null);
      cloud('suppliers/$supplierId/balanceHistory/${entry.id}', deleted: true);
    }
    for (final suffix in ['buying', 'pay']) {
      cloud('suppliers/$supplierId/balanceHistory/${invoiceId}_$suffix',
          deleted: true);
    }
  }

  void stockDifference(List<Map<String, dynamic>> oldLines,
      List<Map<String, dynamic>> newLines, DateTime date, dynamic number) {
    final deltas = <String, double>{};
    final newest = <String, Map<String, dynamic>>{};
    void add(List<Map<String, dynamic>> lines, double sign) {
      for (final line in lines) {
        final storedId = line['id']?.toString().trim() ?? '';
        final productId = storedId.isNotEmpty
            ? storedId
            : line['productId']?.toString().trim() ?? '';
        final product = ProductRepository.instance.getById(productId) ??
            ProductRepository.instance
                .findByName(invoiceCatalogProductName(line));
        if (product == null) {
          throw StateError(
              'Product must be cached before saving: ${invoiceCatalogProductName(line)}');
        }
        final quantity = SupplierOperationService._amount(
            line['amount'] ?? line['quantity'] ?? line['count'] ?? line['qty'],
            'quantity');
        deltas[product.id] = (deltas[product.id] ?? 0) + sign * quantity;
        if (sign > 0) newest[product.id] = line;
      }
    }

    add(oldLines, -1);
    add(newLines, 1);
    for (final entry in deltas.entries) {
      final product = productsBox.get(entry.key)!;
      final line = newest[entry.key];
      final updates = <String, dynamic>{};
      if (line != null) {
        for (final pair in const {
          'newCostPrice': 'costPrice',
          'newSellingPrice1': 'sellingPrice1',
          'newSellingPrice2': 'sellingPrice2',
          'newSellingPrice3': 'sellingPrice3',
        }.entries) {
          if (line[pair.key] != null) {
            updates[pair.value] = invoiceNum(line[pair.key]);
          }
        }
      }
      local(HiveBoxNames.products, product.id, {
        ...product.toMap(),
        ...updates,
        'quantity': product.quantity + entry.value,
      });
      cloud('products/${product.id}',
          data: updates, increments: {'quantity': entry.value});
      if (entry.value != 0) {
        cloud('products/${product.id}/changes/$id', data: {
          'date': date,
          'amount': entry.value.abs(),
          'type': entry.value >= 0 ? 'increase' : 'decrease',
          'invoiceNumber': number,
        });
      }
    }
  }

  void cash(double delta, String name, {DateTime? date}) {
    if (delta == 0) return;
    final current = boxCacheBox.get('mainBox')?.value ?? 0;
    local(HiveBoxNames.box, 'mainBox', {
      'value': current + delta,
      'updatedAt': DateTime.now(),
    });
    cloud('box/mainBox', increments: {'value': delta});
    cloud('box/mainBox/changes/$id', data: {
      'date': date ?? DateTime.now(),
      'value': delta.abs(),
      'type': delta >= 0 ? 'addition' : 'subtraction',
      'name': name,
    });
  }

  Map<String, dynamic> finish(Map<String, dynamic> identity) => {
        ...identity,
        'financialFormat': 2,
        'operationType': operationType,
        'description': description,
        'timestamp': DateTime.now(),
        'localWrites': localWrites,
        'cloudWrites': cloudWrites.values.toList(),
        'customerDeltas': <String, double>{},
        'supplierDeltas': supplierDeltas,
      };
}
