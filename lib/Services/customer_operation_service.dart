import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/balance_history_local.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../sync/local_operation_journal.dart';
import '../sync/cloud_snapshot_guard.dart';
import '../sync/financial_cloud_store.dart';
import 'customer_balance_store.dart';
import 'invoice_number_utils.dart';

/// The sole local financial write path for customer operations. Plans contain
/// recoverable Hive after-images and one atomic, idempotent cloud transaction.
class CustomerOperationService {
  static const _uuid = Uuid();

  static bool voucherAddsDebt(String direction) {
    if (direction == 'عليه') return true;
    if (direction == 'له') return false;
    throw ArgumentError('Unknown customer voucher direction');
  }

  static Map<String, dynamic> clientMap(String id) {
    final c = clientsBox.get(id);
    if (c == null) throw StateError('Customer is not available locally: $id');
    return {
      'id': id,
      'clientName': c.name,
      'balance': c.balance,
      'phone': c.phone,
      'address': c.address
    };
  }

  static Future<Map<String, dynamic>> saveQuote(Map<String, dynamic> input,
      {bool editing = false}) async {
    final quoteId = input['id']?.toString() ?? _uuid.v4();
    final data = {
      ...input,
      'id': quoteId,
      'date': input['date'] ?? DateTime.now()
    };
    await LocalOperationJournal.commit((id) async {
      final old = quotesBox.get(quoteId);
      if (editing && old == null)
        throw StateError('Quote must be cached before editing');
      if (!editing && old != null) throw StateError('Quote already saved');
      if (appMetaBox.containsKey('executedQuote:' + quoteId))
        throw StateError('Quote already executed');
      final plan =
          _Plan(id, editing ? 'editQuote' : 'createQuote', 'حفظ عرض سعر');
      plan.local(HiveBoxNames.quotes, quoteId, data);
      plan.cloud('price_quotes/' + quoteId,
          data: data, absent: !editing, expected: old?.toMap());
      return plan.finish({'quoteId': quoteId});
    });
    return data;
  }

  static Future<void> deleteQuote(String quoteId) =>
      LocalOperationJournal.commit((id) async {
        final old = quotesBox.get(quoteId);
        if (old == null)
          throw StateError('Quote must be cached before deleting');
        final plan = _Plan(id, 'deleteQuote', 'حذف عرض سعر');
        plan.local(HiveBoxNames.quotes, quoteId, null);
        plan.cloud('price_quotes/' + quoteId,
            deleted: true, expected: old.toMap());
        return plan.finish({'quoteId': quoteId});
      }).then((_) {});

  static Future<String> createClient(
      {required String name,
      required double openingBalance,
      String phone = '',
      String address = ''}) async {
    final clientId = _uuid.v4();
    await LocalOperationJournal.commit((id) async {
      if (ClientRepository.instance.findByName(name) != null)
        throw StateError('Customer already exists');
      final plan = _Plan(id, 'createClient', 'إنشاء عميل');
      final data = {
        'id': clientId,
        'clientName': name,
        'name': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
        'balance': 0.0
      };
      plan.local(
          HiveBoxNames.appMeta, CustomerBalanceStore.baseKey(clientId), 0.0);
      plan.cloud('clients/$clientId', data: data, absent: true);
      plan.customer(clientId, openingBalance, initial: data);
      if (openingBalance != 0) {
        plan.history(BalanceHistoryLocal(
            id: '${clientId}_opening',
            parentId: clientId,
            parentType: 'client',
            enteredBalance: openingBalance,
            type: 'opening',
            timestamp: DateTime.now()));
      }
      return plan.finish({
        'clientId': clientId,
        'openingBalance': openingBalance,
        'openingHistoryId': '${clientId}_opening',
        'data': data
      });
    });
    return clientId;
  }

  static Future<Map<String, dynamic>> saveInvoice(Map<String, dynamic> input,
      {bool isReturn = false,
      bool editing = false,
      String? clientSubDocId,
      String? quoteId}) async {
    late Map<String, dynamic> saved;
    await LocalOperationJournal.commit((id) async {
      final invoiceId = quoteId == null
          ? (input['invoiceId'] ?? input['id'])?.toString() ?? _uuid.v4()
          : 'quote_sale_' + quoteId;
      if (quoteId != null && appMetaBox.containsKey('executedQuote:' + quoteId))
        throw StateError('Quote already executed');
      final collection = isReturn ? 'returnInvoices' : 'invoices';
      final box = isReturn ? returnInvoicesBox : invoicesBox;
      final old = box.get(invoiceId)?.toMap();
      if (editing && old == null)
        throw StateError('Invoice must be cached before editing');
      if (!editing && old != null) throw StateError('Invoice already saved');
      final data = Map<String, dynamic>.from(input);
      final clientName = data['clientName']?.toString() ?? '';
      final clientId = (data['clientId']?.toString().isNotEmpty == true)
          ? data['clientId'].toString()
          : ClientRepository.instance.findByName(clientName)?.id ?? '';
      final client = clientMap(clientId);
      final total = invoiceTryParseAmount(data['totalSum']);
      final paid = invoiceTryParseAmount(data['paidAmount'] ?? 0);
      if (total == null || paid == null || total < 0 || paid < 0)
        throw ArgumentError('Invalid invoice amounts');
      final sign = isReturn ? -1.0 : 1.0;
      final newEffect = sign * (total - paid);
      final oldEffect = old == null ? 0.0 : sign * invoiceUnpaidAmount(old);
      final storedOldClient = old?['clientId']?.toString() ?? '';
      final oldClientId = old == null
          ? clientId
          : storedOldClient.isNotEmpty
              ? storedOldClient
              : ClientRepository.instance
                      .findByName(old['clientName']?.toString() ?? '')
                      ?.id ??
                  '';
      if (old != null) clientMap(oldClientId);
      final operationType = editing
          ? 'editInvoice'
          : isReturn
              ? 'createReturn'
              : 'createInvoice';
      final plan =
          _Plan(id, operationType, editing ? 'تعديل فاتورة' : 'حفظ فاتورة');
      final previous = CustomerBalanceStore.balance(clientId,
          fallback: invoiceNum(client['balance']));
      data.addAll({
        'id': invoiceId,
        'invoiceId': invoiceId,
        'clientId': clientId,
        'invoiceType': isReturn ? 'return' : 'sale',
        'invoiceRemaining': total - paid,
        'previousBalance': old?['previousBalance'] ?? previous,
        'balance':
            (old == null ? previous : invoiceNum(old['previousBalance'])) +
                newEffect,
        'date': data['date'] is Timestamp
            ? (data['date'] as Timestamp).toDate()
            : data['date'] ?? DateTime.now(),
        'updatedAt': DateTime.now()
      });
      final lines = _lines(data);
      final frozenLines = <Map<String, dynamic>>[];
      for (final line in lines) {
        final product = _product(line);
        frozenLines.add({
          ...line,
          'id': product.id,
          'costPrice': line['costPrice'] ?? product.costPrice
        });
      }
      data['products'] = frozenLines;
      data['profitMargin'] = sign *
          (total -
              frozenLines.fold<double>(0,
                  (sum, p) => sum + invoiceNum(p['costPrice']) * _quantity(p)));
      if (clientSubDocId != null && clientSubDocId != invoiceId)
        plan.local(
            HiveBoxNames.appMeta,
            'customerInvoiceAlias:' + collection + ':' + clientSubDocId,
            invoiceId);
      final path = '$collection/$invoiceId';
      plan.local(isReturn ? HiveBoxNames.returnInvoices : HiveBoxNames.invoices,
          invoiceId, data);
      plan.cloud(path, data: data, absent: !editing, expected: old);
      if (old != null) {
        plan.removeInvoiceHistory(oldClientId, invoiceId, isReturn);
        if (oldClientId != clientId) {
          plan.customer(oldClientId, -oldEffect);
          plan.cloud(
              'clients/$oldClientId/$collection/${clientSubDocId ?? invoiceId}',
              deleted: true);
        }
      }
      plan.customer(
          clientId, newEffect - (oldClientId == clientId ? oldEffect : 0));
      plan.cloud('clients/$clientId/$collection/$invoiceId', data: data);
      if (clientSubDocId != null && clientSubDocId != invoiceId) {
        plan.cloud('clients/$oldClientId/$collection/$clientSubDocId',
            deleted: true);
      }
      plan.invoiceHistory(clientId, data, isReturn);
      final stockDelta = <String, double>{};
      for (final line in old == null ? <Map<String, dynamic>>[] : _lines(old)) {
        final product = _product(line);
        stockDelta[product.id] =
            (stockDelta[product.id] ?? 0) + sign * _quantity(line);
      }
      for (final line in frozenLines) {
        final product = _product(line);
        stockDelta[product.id] =
            (stockDelta[product.id] ?? 0) - sign * _quantity(line);
      }
      plan.stock(stockDelta, data['date'], data['invoiceNumber']);
      plan.cash(sign * (paid - invoiceNum(old?['paidAmount'])), clientName);
      if (quoteId != null) {
        plan.local(HiveBoxNames.quotes, quoteId, null);
        plan.local(HiveBoxNames.appMeta, 'executedQuote:' + quoteId, invoiceId);
        plan.cloud('price_quotes/' + quoteId, deleted: true);
      }
      saved = data;
      return plan.finish({'clientId': clientId, 'invoiceId': invoiceId});
    });
    return saved;
  }

  static Future<void> deleteInvoice(String invoiceId,
      {bool isReturn = false, String? clientSubDocId}) async {
    await LocalOperationJournal.commit((id) async {
      final old = (isReturn ? returnInvoicesBox : invoicesBox).get(invoiceId);
      if (old == null)
        throw StateError('Invoice must be cached before deleting');
      final data = old.toMap();
      final clientId = old.clientId.isNotEmpty
          ? old.clientId
          : ClientRepository.instance.findByName(old.clientName)?.id ?? '';
      final sign = isReturn ? -1.0 : 1.0;
      final collection = isReturn ? 'returnInvoices' : 'invoices';
      final plan =
          _Plan(id, isReturn ? 'deleteReturn' : 'deleteInvoice', 'حذف فاتورة');
      plan.customer(clientId, -sign * (old.totalSum - old.paidAmount));
      plan.local(isReturn ? HiveBoxNames.returnInvoices : HiveBoxNames.invoices,
          invoiceId, null);
      plan.local(HiveBoxNames.appMeta,
          'deletedCustomerInvoice:$collection:$invoiceId', true);
      plan.cloud('$collection/$invoiceId', deleted: true, expected: data);
      plan.cloud('clients/$clientId/$collection/$invoiceId', deleted: true);
      if (clientSubDocId != null && clientSubDocId != invoiceId)
        plan.cloud('clients/$clientId/$collection/$clientSubDocId',
            deleted: true);
      plan.removeInvoiceHistory(clientId, invoiceId, isReturn);
      final deltas = <String, double>{};
      for (final line in _lines(data)) {
        final product = _product(line);
        deltas[product.id] = (deltas[product.id] ?? 0) + sign * _quantity(line);
      }
      plan.stock(deltas, DateTime.now(), old.invoiceNumber);
      plan.cash(-sign * old.paidAmount, old.clientName);
      return plan.finish({
        'clientId': clientId,
        'clientName': old.clientName,
        'invoiceId': invoiceId,
        'invoiceNumber': old.invoiceNumber,
        'totalSum': old.totalSum,
      });
    });
  }

  static Future<void> savePayment(
      {required String clientId,
      required double amount,
      required bool isAddition,
      required String notes,
      DateTime? date,
      String? historyId,
      bool deleting = false,
      Map<String, dynamic>? voucher}) async {
    if (!amount.isFinite || amount < 0) throw ArgumentError('Invalid payment');
    await LocalOperationJournal.commit((id) async {
      final entryId = historyId ?? id;
      final key = 'client_${clientId}_$entryId';
      final old = balanceHistoryBox.get(key);
      if (historyId != null && old == null)
        throw StateError('Payment must be cached before editing');
      if (old != null &&
          !['addition', 'deduction', 'opening'].contains(old.type))
        throw StateError('Edit the linked invoice instead');
      final type = old?.type ?? (isAddition ? 'addition' : 'deduction');
      final sign = type == 'deduction' ? -1.0 : 1.0;
      final delta =
          sign * ((deleting ? 0 : amount) - (old?.enteredBalance ?? 0));
      final plan =
          _Plan(id, 'adjustClientBalance', deleting ? 'حذف دفعة' : 'حفظ دفعة');
      plan.customer(clientId, delta);
      final entry = BalanceHistoryLocal(
          id: entryId,
          parentId: clientId,
          parentType: 'client',
          enteredBalance: amount,
          type: type,
          notes: notes,
          timestamp: date ?? old?.timestamp ?? DateTime.now());
      if (deleting) {
        plan.local(HiveBoxNames.balanceHistory, key, null);
        plan.cloud('clients/$clientId/balanceHistory/$entryId',
            deleted: true, expected: old!.toMap());
      } else {
        plan.history(entry, expected: old?.toMap());
      }
      if (type != 'opening')
        plan.cash(-delta, clientMap(clientId)['clientName'].toString());
      if (voucher != null) {
        plan.local(HiveBoxNames.appMeta, 'customerVoucher:$entryId',
            {...voucher, 'id': entryId});
        plan.cloud('client_vouchers/$entryId', data: voucher, absent: true);
      } else if (appMetaBox.containsKey('customerVoucher:$entryId')) {
        final oldVoucher = Map<String, dynamic>.from(
            appMetaBox.get('customerVoucher:$entryId') as Map);
        final updated = {...oldVoucher, 'amount': amount, 'description': notes};
        plan.local(HiveBoxNames.appMeta, 'customerVoucher:$entryId',
            deleting ? null : updated);
        plan.cloud('client_vouchers/$entryId',
            data: updated, deleted: deleting);
      }
      return plan.finish({'clientId': clientId, 'historyId': entryId});
    });
  }

  static Future<void> changeCash(double delta,
          {String name = '', DateTime? date}) =>
      LocalOperationJournal.commit((id) async {
        final plan = _Plan(id, 'updateBox', 'تعديل الصندوق');
        plan.cash(delta, name, date: date);
        return plan.finish({});
      }).then((_) {});

  static List<Map<String, dynamic>> _lines(Map<String, dynamic> invoice) =>
      (invoice['products'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
  static double _quantity(Map<String, dynamic> line) {
    final result = invoiceTryParseAmount(
        line['amount'] ?? line['quantity'] ?? line['count'] ?? line['qty']);
    if (result == null || result < 0)
      throw ArgumentError('Invalid stock quantity');
    return result;
  }

  static dynamic _product(Map<String, dynamic> line) {
    final productId = (line['id'] ?? line['productId'])?.toString() ?? '';
    final product = ProductRepository.instance.getById(productId) ??
        ProductRepository.instance.findByName(invoiceCatalogProductName(line));
    if (product == null)
      throw StateError(
          'Product must be cached before saving: ${invoiceCatalogProductName(line)}');
    return product;
  }
}

class _Plan {
  final String id, operationType, description;
  final localWrites = <Map<String, dynamic>>[];
  final cloudWrites = <String, Map<String, dynamic>>{};
  final customerDeltas = <String, double>{};
  _Plan(this.id, this.operationType, this.description);
  void local(String box, String key, dynamic data) {
    localWrites.removeWhere((w) => w['box'] == box && w['key'] == key);
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
      'mustBeAbsent': absent
    };
    if (expected != null) {
      write['expectedOperationId'] = appMetaBox
          .get(CloudSnapshotGuard.operationKey(path), defaultValue: '');
      if (expected.containsKey('products'))
        write['expectedFinancialState'] = financialInvoiceState(expected);
      write['expectedFields'] = {
        for (final key in ['totalSum', 'paidAmount', 'enteredBalance'])
          if (expected.containsKey(key)) key: expected[key]
      };
    }
    cloudWrites[path] = write;
    local(HiveBoxNames.appMeta, CloudSnapshotGuard.operationKey(path), id);
  }

  void customer(String clientId, double delta,
      {Map<String, dynamic>? initial}) {
    final data = initial ?? CustomerOperationService.clientMap(clientId);
    if (!CustomerBalanceStore.hasBase(clientId) && initial == null) {
      local(HiveBoxNames.appMeta, CustomerBalanceStore.baseKey(clientId),
          invoiceNum(data['balance']));
    }
    customerDeltas[clientId] = (customerDeltas[clientId] ?? 0) + delta;
    final total = customerDeltas[clientId]!;
    final before = initial == null
        ? CustomerBalanceStore.balance(clientId,
            fallback: invoiceNum(data['balance']))
        : 0.0;
    local(HiveBoxNames.appMeta, CustomerBalanceStore.eventKey(clientId, id), {
      'delta': total,
      'operationId': id,
      'timestamp': DateTime.now(),
      'description': description
    });
    local(HiveBoxNames.clients, clientId, {...data, 'balance': before + total});
  }

  void history(BalanceHistoryLocal entry, {Map<String, dynamic>? expected}) {
    local(HiveBoxNames.balanceHistory, 'client_${entry.parentId}_${entry.id}',
        {...entry.toMap(), 'parentId': entry.parentId, 'parentType': 'client'});
    cloud('clients/${entry.parentId}/balanceHistory/${entry.id}',
        data: entry.toMap(), expected: expected);
  }

  void invoiceHistory(
      String clientId, Map<String, dynamic> data, bool isReturn) {
    final invoiceId = data['id'].toString();
    final total = invoiceNum(data['totalSum']),
        paid = invoiceNum(data['paidAmount']);
    final date = data['date'];
    final timestamp = date is DateTime ? date : DateTime.parse(date.toString());
    history(BalanceHistoryLocal(
        id: '${invoiceId}_${isReturn ? 'return' : 'sale'}',
        parentId: clientId,
        parentType: 'client',
        enteredBalance: total,
        type: isReturn ? 'return' : 'sale',
        invoiceId: invoiceId,
        invoiceNumber: data['invoiceNumber'].toString(),
        timestamp: timestamp));
    if (paid > 0)
      history(BalanceHistoryLocal(
          id: '${invoiceId}_${isReturn ? 'return_pay' : 'pay'}',
          parentId: clientId,
          parentType: 'client',
          enteredBalance: paid,
          type: isReturn ? 'return_payment' : 'sale_payment',
          invoiceId: invoiceId,
          invoiceNumber: data['invoiceNumber'].toString(),
          timestamp: timestamp));
  }

  void removeInvoiceHistory(String clientId, String invoiceId, bool isReturn) {
    for (final entry in balanceHistoryBox.values
        .where((e) =>
            e.parentType == 'client' &&
            e.parentId == clientId &&
            (e.invoiceId == invoiceId ||
                appMetaBox.get('customerInvoiceAlias:' +
                        (isReturn ? 'returnInvoices' : 'invoices') +
                        ':' +
                        e.invoiceId) ==
                    invoiceId ||
                e.id == '${invoiceId}_sale' ||
                e.id == '${invoiceId}_pay' ||
                e.id == '${invoiceId}_return' ||
                e.id == '${invoiceId}_return_pay'))
        .toList()) {
      local(
          HiveBoxNames.balanceHistory, 'client_${clientId}_${entry.id}', null);
      cloud('clients/$clientId/balanceHistory/${entry.id}', deleted: true);
    }
    // Ensure canonical rows absent locally are still removed remotely.
    for (final suffix
        in isReturn ? ['return', 'return_pay'] : ['sale', 'pay']) {
      cloud('clients/$clientId/balanceHistory/${invoiceId}_$suffix',
          deleted: true);
    }
  }

  void stock(Map<String, double> deltas, dynamic date, dynamic number) {
    for (final entry in deltas.entries) {
      if (entry.value == 0) continue;
      final product = productsBox.get(entry.key)!;
      local(HiveBoxNames.products, product.id,
          {...product.toMap(), 'quantity': product.quantity + entry.value});
      cloud('products/${product.id}', increments: {'quantity': entry.value});
      cloud('products/${product.id}/changes/$id', data: {
        'date': date,
        'amount': entry.value.abs(),
        'type': entry.value >= 0 ? 'increase' : 'decrease',
        'invoiceNumber': number
      });
    }
  }

  void cash(double delta, String name, {DateTime? date}) {
    if (delta == 0) return;
    final current = boxCacheBox.get('mainBox')?.value ?? 0;
    local(HiveBoxNames.box, 'mainBox',
        {'value': current + delta, 'updatedAt': DateTime.now()});
    cloud('box/mainBox', increments: {'value': delta});
    cloud('box/mainBox/changes/$id', data: {
      'date': date ?? DateTime.now(),
      'value': delta.abs(),
      'type': delta >= 0 ? 'addition' : 'subtraction',
      'name': name
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
        'customerDeltas': customerDeltas,
      };
}
