import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Services/invoice_number_utils.dart';

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
  Future<Map<String, dynamic>?> readDocument(String path) async =>
      (await FirebaseFirestore.instance.doc(path).get()).data();
  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
      String clientId) async {
    final snap = await FirebaseFirestore.instance
        .collection('clients')
        .doc(clientId)
        .collection('financialOperations')
        .get();
    return {for (final doc in snap.docs) doc.id: doc.data()};
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readSupplierEvents(
      String supplierId) async {
    final snap = await FirebaseFirestore.instance
        .collection('suppliers')
        .doc(supplierId)
        .collection('financialOperations')
        .get();
    return {for (final doc in snap.docs) doc.id: doc.data()};
  }

  @override
  Future<Map<String, dynamic>> transaction(
          Future<Map<String, dynamic>> Function(FinancialTransaction tx)
              action) =>
      FirebaseFirestore.instance
          .runTransaction((tx) => action(_FirestoreTransaction(tx)));
}

class _FirestoreTransaction implements FinancialTransaction {
  final Transaction transaction;
  _FirestoreTransaction(this.transaction);
  @override
  Future<Map<String, dynamic>?> read(String path) async =>
      (await transaction.get(FirebaseFirestore.instance.doc(path))).data();
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
      final paths = <String>{
        ...writes.map((w) => w['path'] as String),
        ...deltas.keys.map((id) => 'clients/$id'),
        ...supplierDeltas.keys.map((id) => 'suppliers/$id')
      };
      final before = <String, Map<String, dynamic>?>{};
      for (final path in paths) {
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
