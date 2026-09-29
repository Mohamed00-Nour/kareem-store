import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Services/invoice_number_utils.dart';
import 'firestore_read_diagnostics.dart';

abstract class FinancialTransaction {
  Future<Map<String, dynamic>?> read(String path);
  void write(String path, Map<String, dynamic> data);
}

abstract class FinancialCloudStore {
  Future<Map<String, dynamic>> transaction(
      Future<Map<String, dynamic>> Function(FinancialTransaction tx) action);

  Future<Map<String, dynamic>?> readDocument(String path) async {
    final result =
        await transaction((tx) async => {'record': await tx.read(path)});
    return result['record'] as Map<String, dynamic>?;
  }

  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(String clientId);

  Future<Map<String, Map<String, dynamic>>> readSupplierEvents(
          String supplierId) async =>
      const {};
}

class FirestoreFinancialCloudStore implements FinancialCloudStore {
  @override
  Future<Map<String, dynamic>?> readDocument(String path) async {
    try {
      final snapshot = await FirebaseFirestore.instance.doc(path).get();
      FirestoreReadDiagnostics.queryResult(
        'document $path',
        snapshot.exists ? 1 : 0,
        trigger: 'post-upload financial refresh',
        fromCache: snapshot.metadata.isFromCache,
      );
      return snapshot.data();
    } catch (error) {
      FirestoreReadDiagnostics.queryError(
        'document $path',
        error,
        trigger: 'post-upload financial refresh',
      );
      rethrow;
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
      String clientId) async {
    const trigger = 'legacy balance compatibility fallback';
    final identity = 'clients/$clientId/financialOperations full scan';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .collection('financialOperations')
          .get();
      FirestoreReadDiagnostics.queryResult(
        identity,
        snap.docs.length,
        trigger: trigger,
        fromCache: snap.metadata.isFromCache,
      );
      return {for (final doc in snap.docs) doc.id: doc.data()};
    } catch (error) {
      FirestoreReadDiagnostics.queryError(
        identity,
        error,
        trigger: trigger,
      );
      rethrow;
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readSupplierEvents(
      String supplierId) async {
    const trigger = 'legacy balance compatibility fallback';
    final identity = 'suppliers/$supplierId/financialOperations full scan';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('suppliers')
          .doc(supplierId)
          .collection('financialOperations')
          .get();
      FirestoreReadDiagnostics.queryResult(
        identity,
        snap.docs.length,
        trigger: trigger,
        fromCache: snap.metadata.isFromCache,
      );
      return {for (final doc in snap.docs) doc.id: doc.data()};
    } catch (error) {
      FirestoreReadDiagnostics.queryError(
        identity,
        error,
        trigger: trigger,
      );
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> transaction(
          Future<Map<String, dynamic>> Function(FinancialTransaction tx)
              action) =>
      FirebaseFirestore.instance.runTransaction((tx) {
        // Firestore can re-run this callback after contention. Recording each
        // invocation makes retries visible without uploading telemetry.
        FirestoreReadDiagnostics.transactionAttempt('financial upload');
        return action(_FirestoreTransaction(tx));
      });
}

class _FirestoreTransaction implements FinancialTransaction {
  final Transaction transaction;
  _FirestoreTransaction(this.transaction);
  @override
  Future<Map<String, dynamic>?> read(String path) async {
    final snapshot =
        await transaction.get(FirebaseFirestore.instance.doc(path));
    FirestoreReadDiagnostics.transactionRead(
      path,
      exists: snapshot.exists,
    );
    return snapshot.data();
  }

  @override
  void write(String path, Map<String, dynamic> data) =>
      transaction.set(FirebaseFirestore.instance.doc(path), _cloudDates(data));

  static Map<String, dynamic> _cloudDates(Map<String, dynamic> data) =>
      data.map((key, value) {
        if (value is Map) value = _cloudDates(Map<String, dynamic>.from(value));
        if (value is List)
          value = value
              .map((item) => item is Map
                  ? _cloudDates(Map<String, dynamic>.from(item))
                  : item)
              .toList();
        if (value is String &&
            ['date', 'timestamp', 'createdAt', 'updatedAt'].contains(key)) {
          value = DateTime.tryParse(value) ?? value;
        }
        return MapEntry(key, value);
      });
}

/// The same transaction algorithm is used by production and in-memory tests.
/// All reads precede writes; the receipt and every financial effect commit
/// together. No reconnect-time history repair or balance assignment occurs.
class FinancialCloudUploader {
  static const String feedHeadPath =
      'financial_operation_receipts/_change_feed_head';

  static Future<Map<String, dynamic>> upload(String operationId,
      Map<String, dynamic> payload, FinancialCloudStore store) {
    return store.transaction((tx) async {
      final markerPath = 'financial_operation_receipts/$operationId';
      final existing = await tx.read(markerPath);
      if (existing != null) return existing;
      final feedHead = await tx.read(feedHeadPath);
      final sequence = invoiceNum(feedHead?['lastSequence']).toInt() + 1;
      final writes = (payload['cloudWrites'] as List)
          .map((w) => Map<String, dynamic>.from(w as Map))
          .toList();
      final deltas =
          Map<String, dynamic>.from(payload['customerDeltas'] as Map);
      final supplierDeltas = Map<String, dynamic>.from(
          payload['supplierDeltas'] as Map? ?? const {});
      final preloaded = <String, Map<String, dynamic>?>{};
      final operationType = payload['operationType']?.toString() ?? '';
      if (operationType == 'deleteBuyingInvoice' &&
          payload['financialFormat'] == 2) {
        final invoiceId = payload['invoiceId']?.toString().trim() ?? '';
        if (invoiceId.isEmpty) {
          throw StateError('Invalid purchase invoice id');
        }
        final rootPath = 'buying invoices/$invoiceId';
        final latestInvoice = await tx.read(rootPath);
        preloaded[rootPath] = latestInvoice;
        _rebaseBuyingInvoiceDelete(
          operationId: operationId,
          payload: payload,
          writes: writes,
          supplierDeltas: supplierDeltas,
          latestInvoice: latestInvoice,
        );
      } else if (const {
            'deleteInvoice',
            'deleteReturn',
            'deleteReturnInvoice',
          }.contains(operationType) &&
          payload['financialFormat'] == 2) {
        final invoiceId = payload['invoiceId']?.toString().trim() ?? '';
        if (invoiceId.isEmpty) {
          throw StateError('Invalid customer invoice id');
        }
        final isReturn = operationType != 'deleteInvoice';
        final collection = isReturn ? 'returnInvoices' : 'invoices';
        final rootPath = '$collection/$invoiceId';
        final latestInvoice = await tx.read(rootPath);
        preloaded[rootPath] = latestInvoice;
        _rebaseCustomerInvoiceDelete(
          operationId: operationId,
          payload: payload,
          writes: writes,
          customerDeltas: deltas,
          latestInvoice: latestInvoice,
          isReturn: isReturn,
        );
      }
      final paths = <String>{
        ...writes.map((w) => w['path'] as String),
        ...deltas.keys.map((id) => 'clients/$id'),
        ...supplierDeltas.keys.map((id) => 'suppliers/$id')
      };
      final before = <String, Map<String, dynamic>?>{...preloaded};
      for (final path in paths) {
        if (before.containsKey(path)) continue;
        before[path] = await tx.read(path);
      }
      final after = <String, Map<String, dynamic>>{};
      final versions = <String, int>{};
      for (final write in writes) {
        final path = write['path'] as String;
        final old = before[path];
        if (write['mustBeAbsent'] == true &&
            old != null &&
            old['_deleted'] != true) {
          throw StateError(
              'Record already exists: $path; review before retrying');
        }
        if (write.containsKey('expectedOperationId') &&
            (old == null || old['_deleted'] == true))
          throw StateError('Record missing or deleted: ' +
              path +
              '; review before retrying');
        if (path.startsWith('products/') &&
            path.split('/').length == 2 &&
            (write['increments'] as Map? ?? {}).isNotEmpty &&
            (old == null || old['_deleted'] == true))
          throw StateError('Product missing: ' + path);
        if (write['expectedFinancialState'] != null &&
            jsonEncode(financialInvoiceState(old!)) !=
                jsonEncode(write['expectedFinancialState']))
          throw StateError('Invoice lines or customer changed: ' +
              path +
              '; review before retrying');
        if (write.containsKey('expectedOperationId') &&
            (old?['_operationId'] ?? '') != write['expectedOperationId']) {
          throw StateError(
              'Concurrent change to $path; review before retrying');
        }
        final expected = write['expectedFields'] as Map?;
        if (expected != null && old != null) {
          for (final field in expected.keys) {
            final remote = old[field];
            final wanted = expected[field];
            final equal =
                wanted is num ? invoiceNum(remote) == wanted : remote == wanted;
            if (!equal)
              throw StateError(
                  'Historical $field changed in $path; review before retrying');
          }
        }
        final data = <String, dynamic>{
          ...?old,
          ...?write['data'] as Map<String, dynamic>?
        };
        for (final entry in (write['increments'] as Map? ?? {}).entries) {
          data[entry.key.toString()] =
              invoiceNum(data[entry.key]) + invoiceNum(entry.value);
        }
        data['_deleted'] = write['deleted'] == true;
        data['_version'] = invoiceNum(old?['_version']).toInt() + 1;
        data['_operationId'] = operationId;
        after[path] = data;
        versions[path] = data['_version'] as int;
      }
      for (final entry in deltas.entries) {
        final path = 'clients/${entry.key}';
        if (before[path] == null && !after.containsKey(path))
          throw StateError('Customer missing: ' + path);
        if (before[path]?['_deleted'] == true)
          throw StateError('Customer archived: ' + path);
        final old = before[path] ?? <String, dynamic>{};
        final data = after[path] ?? Map<String, dynamic>.from(old);
        final base = invoiceNum(old['financialBaseBalance'] ?? old['balance']);
        data['financialBaseBalance'] = base;
        data['balance'] = invoiceNum(old['balance']) + invoiceNum(entry.value);
        data['financialVersion'] =
            invoiceNum(old['financialVersion']).toInt() + 1;
        data['_version'] = invoiceNum(old['_version']).toInt() + 1;
        data['_operationId'] = operationId;
        after[path] = data;
        versions[path] = data['_version'] as int;
      }
      for (final entry in supplierDeltas.entries) {
        final path = 'suppliers/${entry.key}';
        if (before[path] == null && !after.containsKey(path))
          throw StateError('Supplier missing: ' + path);
        if (before[path]?['_deleted'] == true)
          throw StateError('Supplier archived: ' + path);
        final old = before[path] ?? <String, dynamic>{};
        final data = after[path] ?? Map<String, dynamic>.from(old);
        final oldBalance = invoiceNum(old['totalBalance'] ?? old['balance']);
        final base = invoiceNum(old['financialBaseBalance'] ?? oldBalance);
        final newBalance = oldBalance + invoiceNum(entry.value);
        data['financialBaseBalance'] = base;
        data['balance'] = newBalance;
        data['totalBalance'] = newBalance;
        data['financialVersion'] =
            invoiceNum(old['financialVersion']).toInt() + 1;
        data['_version'] = invoiceNum(old['_version']).toInt() + 1;
        data['_operationId'] = operationId;
        after[path] = data;
        versions[path] = data['_version'] as int;
      }
      if (after.length + deltas.length + supplierDeltas.length + 2 > 450)
        throw StateError('Operation exceeds atomic upload limit');
      for (final entry in after.entries) {
        tx.write(entry.key, entry.value);
      }
      for (final entry in deltas.entries) {
        tx.write('clients/${entry.key}/financialOperations/$operationId', {
          'clientId': entry.key,
          'operationId': operationId,
          'delta': entry.value,
          'description': payload['description'],
          'timestamp': payload['timestamp'],
        });
      }
      for (final entry in supplierDeltas.entries) {
        tx.write('suppliers/${entry.key}/financialOperations/$operationId', {
          'supplierId': entry.key,
          'operationId': operationId,
          'delta': entry.value,
          'description': payload['description'],
          'timestamp': payload['timestamp'],
        });
      }
      final receipt = <String, dynamic>{
        'versions': versions,
        'operationId': operationId,
        'sequence': sequence,
        'customerIds': deltas.keys.toList(),
        'supplierIds': supplierDeltas.keys.toList(),
        'timestamp': payload['timestamp'],
      };
      tx.write(markerPath, receipt);
      tx.write(feedHeadPath, {
        'lastSequence': sequence,
        'lastOperationId': operationId,
        'updatedAt': payload['timestamp'],
      });
      return receipt;
    });
  }

  /// A delete is the user's intent for the invoice currently stored in the
  /// cloud, even if another device edited it after this device queued the
  /// action. Rebuild all financial reversals from that latest invoice while
  /// still inside the atomic transaction. This avoids both a needless conflict
  /// and the much worse alternative of applying stale stock/cash/balance data.
  static void _rebaseBuyingInvoiceDelete({
    required String operationId,
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> writes,
    required Map<String, dynamic> supplierDeltas,
    required Map<String, dynamic>? latestInvoice,
  }) {
    final invoiceId = payload['invoiceId'].toString();

    bool isProductEffect(String path) {
      final parts = path.split('/');
      return parts.isNotEmpty && parts.first == 'products';
    }

    bool isCashEffect(String path) {
      final parts = path.split('/');
      return parts.isNotEmpty && parts.first == 'box';
    }

    bool isInvoiceCopy(String path) {
      final parts = path.split('/');
      return parts.length == 4 &&
          parts[0] == 'suppliers' &&
          parts[2] == 'buying invoices' &&
          parts[3] == invoiceId;
    }

    void removeConflictExpectation(Map<String, dynamic> write) {
      write
        ..remove('expectedOperationId')
        ..remove('expectedFinancialState')
        ..remove('expectedFields');
    }

    void putWrite(Map<String, dynamic> write) {
      final path = write['path'] as String;
      final index = writes.indexWhere((item) => item['path'] == path);
      if (index < 0) {
        writes.add(write);
      } else {
        writes[index] = write;
      }
    }

    // The old payload's product and cash increments describe the stale local
    // invoice. They are replaced below from the latest cloud invoice.
    writes.removeWhere((write) {
      final path = write['path']?.toString() ?? '';
      return isProductEffect(path) || isCashEffect(path);
    });

    for (final write in writes) {
      final path = write['path']?.toString() ?? '';
      if (path == 'buying invoices/$invoiceId' || isInvoiceCopy(path)) {
        removeConflictExpectation(write);
      }
    }

    // Keep an event for every supplier that the local delete previously
    // affected. A zero delta lets the acknowledged cloud result replace that
    // stale local event when the latest invoice belongs to another supplier or
    // was already deleted elsewhere.
    for (final supplierId in supplierDeltas.keys.toList()) {
      supplierDeltas[supplierId] = 0.0;
    }

    final activeInvoice =
        latestInvoice != null && latestInvoice['_deleted'] != true;
    if (!activeInvoice) return;

    final supplierId = latestInvoice['supplierId']?.toString().trim() ?? '';
    if (supplierId.isEmpty) {
      throw StateError('Invalid supplier on latest purchase invoice');
    }
    final total = invoiceNum(latestInvoice['totalSum']);
    final paid = invoiceNum(latestInvoice['paidAmount']);
    supplierDeltas[supplierId] =
        invoiceNum(supplierDeltas[supplierId]) - (total - paid);

    putWrite({
      'path': 'buying invoices/$invoiceId',
      'data': <String, dynamic>{},
      'increments': <String, dynamic>{},
      'deleted': true,
      'mustBeAbsent': false,
    });
    putWrite({
      'path': 'suppliers/$supplierId/buying invoices/$invoiceId',
      'data': <String, dynamic>{},
      'increments': <String, dynamic>{},
      'deleted': true,
      'mustBeAbsent': false,
    });
    for (final suffix in const ['buying', 'pay']) {
      putWrite({
        'path': 'suppliers/$supplierId/balanceHistory/${invoiceId}_$suffix',
        'data': <String, dynamic>{},
        'increments': <String, dynamic>{},
        'deleted': true,
        'mustBeAbsent': false,
      });
    }

    final quantities = <String, double>{};
    for (final raw in latestInvoice['products'] as List? ?? const []) {
      if (raw is! Map) continue;
      final line = Map<String, dynamic>.from(raw);
      final productId =
          (line['id'] ?? line['productId'])?.toString().trim() ?? '';
      if (productId.isEmpty) {
        throw StateError(
            'Product missing immutable id in latest purchase invoice');
      }
      final quantity = invoiceNum(
        line['amount'] ?? line['quantity'] ?? line['count'] ?? line['qty'],
      );
      if (quantity <= 0) continue;
      quantities[productId] = (quantities[productId] ?? 0) + quantity;
    }
    for (final entry in quantities.entries) {
      putWrite({
        'path': 'products/${entry.key}',
        'data': <String, dynamic>{},
        'increments': {'quantity': -entry.value},
        'deleted': false,
        'mustBeAbsent': false,
      });
      putWrite({
        'path': 'products/${entry.key}/changes/$operationId',
        'data': {
          'date': payload['timestamp'],
          'amount': entry.value,
          'type': 'decrease',
          'invoiceNumber': latestInvoice['invoiceNumber'],
        },
        'increments': <String, dynamic>{},
        'deleted': false,
        'mustBeAbsent': false,
      });
    }

    if (paid != 0) {
      putWrite({
        'path': 'box/mainBox',
        'data': <String, dynamic>{},
        'increments': {'value': paid},
        'deleted': false,
        'mustBeAbsent': false,
      });
      putWrite({
        'path': 'box/mainBox/changes/$operationId',
        'data': {
          'date': payload['timestamp'],
          'value': paid.abs(),
          'type': 'addition',
          'name': 'حذف فاتورة مشتريات',
        },
        'increments': <String, dynamic>{},
        'deleted': false,
        'mustBeAbsent': false,
      });
    }
  }

  /// Rebuilds a sale/return deletion from the newest cloud invoice. Sales and
  /// returns have opposite balance, stock, and cash signs, so [isReturn]
  /// controls every reversal from one shared calculation.
  static void _rebaseCustomerInvoiceDelete({
    required String operationId,
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> writes,
    required Map<String, dynamic> customerDeltas,
    required Map<String, dynamic>? latestInvoice,
    required bool isReturn,
  }) {
    final invoiceId = payload['invoiceId'].toString();
    final collection = isReturn ? 'returnInvoices' : 'invoices';

    bool isProductOrCashEffect(String path) {
      final root = path.split('/').first;
      return root == 'products' || root == 'box';
    }

    bool isInvoiceCopy(String path) {
      final parts = path.split('/');
      return parts.length == 4 &&
          parts[0] == 'clients' &&
          parts[2] == collection;
    }

    void putWrite(Map<String, dynamic> write) {
      final path = write['path'] as String;
      final index = writes.indexWhere((item) => item['path'] == path);
      if (index < 0) {
        writes.add(write);
      } else {
        writes[index] = write;
      }
    }

    writes.removeWhere(
        (write) => isProductOrCashEffect(write['path']?.toString() ?? ''));
    for (final write in writes) {
      final path = write['path']?.toString() ?? '';
      if (path == '$collection/$invoiceId' || isInvoiceCopy(path)) {
        write
          ..remove('expectedOperationId')
          ..remove('expectedFinancialState')
          ..remove('expectedFields');
      }
    }
    for (final clientId in customerDeltas.keys.toList()) {
      customerDeltas[clientId] = 0.0;
    }

    if (latestInvoice == null || latestInvoice['_deleted'] == true) return;
    final clientId = latestInvoice['clientId']?.toString().trim() ?? '';
    if (clientId.isEmpty) {
      throw StateError('Invalid customer on latest invoice');
    }
    final sign = isReturn ? -1.0 : 1.0;
    final total = invoiceNum(latestInvoice['totalSum']);
    final paid = invoiceNum(latestInvoice['paidAmount']);
    customerDeltas[clientId] =
        invoiceNum(customerDeltas[clientId]) - sign * (total - paid);

    putWrite({
      'path': '$collection/$invoiceId',
      'data': <String, dynamic>{},
      'increments': <String, dynamic>{},
      'deleted': true,
      'mustBeAbsent': false,
    });
    putWrite({
      'path': 'clients/$clientId/$collection/$invoiceId',
      'data': <String, dynamic>{},
      'increments': <String, dynamic>{},
      'deleted': true,
      'mustBeAbsent': false,
    });
    final historySuffixes =
        isReturn ? const ['return', 'return_pay'] : const ['sale', 'pay'];
    for (final suffix in historySuffixes) {
      putWrite({
        'path': 'clients/$clientId/balanceHistory/${invoiceId}_$suffix',
        'data': <String, dynamic>{},
        'increments': <String, dynamic>{},
        'deleted': true,
        'mustBeAbsent': false,
      });
    }

    final quantities = <String, double>{};
    for (final raw in latestInvoice['products'] as List? ?? const []) {
      if (raw is! Map) continue;
      final line = Map<String, dynamic>.from(raw);
      final productId =
          (line['id'] ?? line['productId'])?.toString().trim() ?? '';
      if (productId.isEmpty) {
        throw StateError('Product missing immutable id in latest invoice');
      }
      final quantity = invoiceNum(
        line['amount'] ?? line['quantity'] ?? line['count'] ?? line['qty'],
      );
      if (quantity <= 0) continue;
      quantities[productId] = (quantities[productId] ?? 0) + quantity;
    }
    for (final entry in quantities.entries) {
      final stockDelta = sign * entry.value;
      putWrite({
        'path': 'products/${entry.key}',
        'data': <String, dynamic>{},
        'increments': {'quantity': stockDelta},
        'deleted': false,
        'mustBeAbsent': false,
      });
      putWrite({
        'path': 'products/${entry.key}/changes/$operationId',
        'data': {
          'date': payload['timestamp'],
          'amount': entry.value,
          'type': stockDelta >= 0 ? 'increase' : 'decrease',
          'invoiceNumber': latestInvoice['invoiceNumber'],
        },
        'increments': <String, dynamic>{},
        'deleted': false,
        'mustBeAbsent': false,
      });
    }

    final cashDelta = -sign * paid;
    if (cashDelta != 0) {
      putWrite({
        'path': 'box/mainBox',
        'data': <String, dynamic>{},
        'increments': {'value': cashDelta},
        'deleted': false,
        'mustBeAbsent': false,
      });
      putWrite({
        'path': 'box/mainBox/changes/$operationId',
        'data': {
          'date': payload['timestamp'],
          'value': cashDelta.abs(),
          'type': cashDelta >= 0 ? 'addition' : 'subtraction',
          'name': payload['description'],
        },
        'increments': <String, dynamic>{},
        'deleted': false,
        'mustBeAbsent': false,
      });
    }
  }
}

/// Normalized financial fields used to reject edits based on stale legacy data.
Map<String, dynamic> financialInvoiceState(Map<String, dynamic> invoice) => {
      'clientId': invoice['clientId']?.toString() ?? '',
      'clientName': invoice['clientName']?.toString() ?? '',
      'supplierId': invoice['supplierId']?.toString() ?? '',
      'supplierName': invoice['supplierName']?.toString() ?? '',
      'totalSum': invoiceNum(invoice['totalSum']),
      'paidAmount': invoiceNum(invoice['paidAmount']),
      'products': (invoice['products'] as List? ?? []).map((raw) {
        final line = Map<String, dynamic>.from(raw as Map);
        return {
          'name': invoiceCatalogProductName(line),
          'quantity': invoiceNum(line['amount'] ??
              line['quantity'] ??
              line['count'] ??
              line['qty']),
          'price': (invoice['supplierId']?.toString() ?? '').isNotEmpty
              ? invoiceBuyingLineUnitPrice(line)
              : invoiceLineUnitPrice(line),
          'total': invoiceNum(line['total'] ?? line['totalCost'])
        };
      }).toList(),
    };
