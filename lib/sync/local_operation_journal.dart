import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../local_db/hive_init.dart';
import '../local_db/models/sync_queue_item.dart';
import '../local_db/models/client_local.dart';
import '../local_db/models/supplier_local.dart';
import '../local_db/models/product_local.dart';
import '../local_db/models/invoice_local.dart';
import '../local_db/models/balance_history_local.dart';
import '../local_db/models/box_local.dart';
import '../local_db/models/quote_local.dart';
import 'sync_operation_diagnostics.dart';

/// Write-ahead outbox. Absolute after-images are flushed before an operation
/// becomes uploadable; recovery can replay any interrupted prefix safely.
class LocalOperationJournal {
  static Future<void> _tail = Future<void>.value();
  static const _uuid = Uuid();

  static Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static dynamic _encode(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    throw ArgumentError('Unsupported journal value: ${value.runtimeType}');
  }

  /// The planner runs under the same lock as recovery and snapshot imports.
  static Future<String> commit(
      Future<Map<String, dynamic>> Function(String id) planner) {
    return exclusive(() async {
      await _recover();
      final id = _uuid.v4();
      final payload = await planner(id);
      var createdMicros = DateTime.now().microsecondsSinceEpoch;
      for (final queued in syncQueueBox.values) {
        if (createdMicros <= queued.createdAt.microsecondsSinceEpoch) {
          createdMicros = queued.createdAt.microsecondsSinceEpoch + 1;
        }
      }
      final item = SyncQueueItem(
          operationId: id,
          operationType:
              payload['operationType']?.toString() ?? 'financialOperation',
          payloadJson: jsonEncode(payload, toEncodable: _encode),
          createdAt: DateTime.fromMicrosecondsSinceEpoch(createdMicros),
          status: 'preparing',
          diagnosticsJson: SyncOperationDiagnostics.fromPayload(
            id,
            payload['operationType']?.toString() ?? 'financialOperation',
            payload,
          ).toJson());
      await syncQueueBox.put(id, item);
      await syncQueueBox.flush();
      await _apply(item);
      return id;
    });
  }

  static Future<void> recover() => exclusive(_recover);
  static Future<void> _recover() async {
    final items = syncQueueBox.values
        .where((e) => e.status == 'preparing')
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final item in items) {
      await _apply(item);
    }
  }

  static Future<void> _apply(SyncQueueItem item) async {
    final payload = jsonDecode(item.payloadJson) as Map;
    for (final raw in payload['localWrites'] as List) {
      final write = Map<String, dynamic>.from(raw as Map);
      final name = write['box'] as String;
      final key = write['key'] as String;
      final Box box;
      switch (name) {
        case HiveBoxNames.clients:
          box = clientsBox;
          break;
        case HiveBoxNames.suppliers:
          box = suppliersBox;
          break;
        case HiveBoxNames.products:
          box = productsBox;
          break;
        case HiveBoxNames.invoices:
          box = invoicesBox;
          break;
        case HiveBoxNames.returnInvoices:
          box = returnInvoicesBox;
          break;
        case HiveBoxNames.buyingInvoices:
          box = buyingInvoicesBox;
          break;
        case HiveBoxNames.buyingReturnInvoices:
          box = buyingReturnInvoicesBox;
          break;
        case HiveBoxNames.balanceHistory:
          box = balanceHistoryBox;
          break;
        case HiveBoxNames.box:
          box = boxCacheBox;
          break;
        case HiveBoxNames.quotes:
          box = quotesBox;
          break;
        case HiveBoxNames.appMeta:
          box = appMetaBox;
          break;
        default:
          throw StateError('Unknown journal box $name');
      }
      final rawData = write['data'];
      if (rawData == null) {
        await box.delete(key);
      } else {
        final data =
            rawData is Map ? Map<String, dynamic>.from(rawData) : rawData;
        dynamic value = data;
        switch (name) {
          case HiveBoxNames.clients:
            value =
                ClientLocal.fromFirestore(key, data as Map<String, dynamic>);
            break;
          case HiveBoxNames.suppliers:
            value =
                SupplierLocal.fromFirestore(key, data as Map<String, dynamic>);
            break;
          case HiveBoxNames.products:
            value =
                ProductLocal.fromFirestore(key, data as Map<String, dynamic>);
            break;
          case HiveBoxNames.invoices:
            value = InvoiceLocal.fromFirestore(
                key, data as Map<String, dynamic>,
                defaultType: 'sale');
            break;
          case HiveBoxNames.returnInvoices:
            value = InvoiceLocal.fromFirestore(
                key, data as Map<String, dynamic>,
                defaultType: 'return');
            break;
          case HiveBoxNames.buyingInvoices:
            value = InvoiceLocal.fromFirestore(
                key, data as Map<String, dynamic>,
                defaultType: 'buying');
            break;
          case HiveBoxNames.buyingReturnInvoices:
            value = InvoiceLocal.fromFirestore(
                key, data as Map<String, dynamic>,
                defaultType: 'buying_return');
            break;
          case HiveBoxNames.balanceHistory:
            final map = data as Map<String, dynamic>;
            value = BalanceHistoryLocal.fromFirestore(map['id'].toString(),
                map['parentId'].toString(), map['parentType'].toString(), map);
            break;
          case HiveBoxNames.box:
            value = BoxLocal.fromFirestore(key, data as Map<String, dynamic>);
            break;
          case HiveBoxNames.quotes:
            value = QuoteLocal.fromFirestore(key, data as Map<String, dynamic>);
            break;
        }
        await box.put(key, value);
      }
      await box.flush();
    }
    item.status = 'pending';
    await item.save();
    await syncQueueBox.flush();
  }
}
