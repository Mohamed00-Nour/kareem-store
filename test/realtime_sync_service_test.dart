// Firestore interfaces are mocked only to drive the production downloader.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kareem_store/Services/customer_balance_store.dart';
import 'package:kareem_store/Services/customer_operation_service.dart';
import 'package:kareem_store/Services/customer_statement_data.dart';
import 'package:kareem_store/Services/invoice_footer_data.dart';
import 'package:kareem_store/Services/supplier_operation_service.dart';
import 'package:kareem_store/Services/supplier_balance_store.dart';
import 'package:kareem_store/repositories/client_repository.dart';
import 'package:kareem_store/repositories/payment_breakdown_repository.dart';
import 'package:kareem_store/local_db/models/payment_breakdown_local.dart';
import 'package:kareem_store/sync/batch_sync_engine.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/local_db/models/invoice_local.dart';
import 'package:kareem_store/local_db/models/sync_queue_item.dart';
import 'package:kareem_store/sync/financial_cloud_store.dart';
import 'package:kareem_store/sync/realtime_sync_service.dart';

class _Metadata implements SnapshotMetadata {
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
  _Metadata({this.isFromCache = false, this.hasPendingWrites = false});
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  final _Cloud cloud;
  @override
  final String path;
  _Document(this.cloud, this.path);
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> get parent =>
      _Collection(cloud, path.substring(0, path.lastIndexOf('/')));
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    cloud.reads.add(MapEntry(path, options?.source));
    if (cloud.failures.contains(path)) throw StateError('network unavailable');
    final metadata = _Metadata(
        isFromCache: cloud.cached.contains(path),
        hasPendingWrites: cloud.pendingWrites.contains(path));
    final data = cloud.documents[path];
    return data == null
        ? _MissingSnapshot(metadata)
        : _Snapshot(cloud, path, data, metadata);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final _Cloud cloud;
  final String path;
  final Map<String, dynamic>? value;
  @override
  final SnapshotMetadata metadata;
  _Snapshot(this.cloud, this.path, this.value, this.metadata);
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _Document(cloud, path);
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic> data() => value!;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// A missing document's data() must return null; query documents always exist.
class _MissingSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final SnapshotMetadata metadata;
  _MissingSnapshot(this.metadata);
  @override
  bool get exists => false;
  @override
  Map<String, dynamic>? data() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
  _QuerySnapshot(this.docs, this.metadata);
  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Query implements Query<Map<String, dynamic>> {
  final _Cloud cloud;
  final String path;
  final bool group;
  final int? cursor;
  _Query(this.cloud, this.path, {this.group = false, this.cursor});
  String get identity => group ? 'group:$path' : path;
  _QuerySnapshot snapshot({bool cached = false}) {
    final docs = cloud.documents.entries
        .where((entry) {
          final parts = entry.key.split('/');
          if (group) {
            return parts.length >= 4 && parts[parts.length - 2] == path;
          }
          if (!entry.key.startsWith('$path/') ||
              parts.length != path.split('/').length + 1) {
            return false;
          }
          return cursor == null ||
              (entry.value['sequence'] as num? ?? 0) > cursor!;
        })
        .map((entry) =>
            _Snapshot(cloud, entry.key, Map.from(entry.value), _Metadata()))
        .toList();
    if (cursor != null) {
      docs.sort((a, b) =>
          (a.value!['sequence'] as num).compareTo(b.value!['sequence'] as num));
    }
    return _QuerySnapshot(
        docs,
        _Metadata(
            isFromCache: cached,
            hasPendingWrites: cloud.pendingWrites.contains(identity)));
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    cloud.reads.add(MapEntry(identity, options?.source));
    if (cloud.permissionFailures.contains(identity)) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
    }
    if (cloud.failures.contains(identity)) {
      throw StateError('network unavailable');
    }
    final result = snapshot(cached: cloud.cached.contains(identity));
    cloud.afterQuery?.call(identity);
    return result;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots(
      {bool includeMetadataChanges = false,
      ListenSource source = ListenSource.defaultSource}) {
    if (path != 'financial_operation_receipts') return const Stream.empty();
    cloud.includeMetadataChanges = includeMetadataChanges;
    return cloud.receiptStream.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _Query(cloud, path,
          group: group,
          cursor: (invocation.namedArguments[#isGreaterThan] as num?)?.toInt());
    }
    if (invocation.memberName == #orderBy) return this;
    return super.noSuchMethod(invocation);
  }
}

class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.cloud, super.path);
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>>? get parent => path.contains('/')
      ? _Document(cloud, path.substring(0, path.lastIndexOf('/')))
      : null;
}

class _Cloud implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final cached = <String>{}, failures = <String>{}, pendingWrites = <String>{};
  final permissionFailures = <String>{};
  final reads = <MapEntry<String, Source?>>[];
  final receiptStream =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  bool includeMetadataChanges = false;
  void Function(String)? afterQuery;
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      _Document(this, path);
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Query<Map<String, dynamic>> collectionGroup(String path) =>
      _Query(this, path, group: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AtomicCloud extends FinancialCloudStore {
  final _Cloud cloud;
  _AtomicCloud(this.cloud);
  @override
  Future<Map<String, dynamic>> transaction(
      Future<Map<String, dynamic>> Function(FinancialTransaction)
          action) async {
    final tx = _AtomicTransaction(cloud.documents);
    final result = await action(tx);
    cloud.documents.addAll(tx.writes);
    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readCustomerEvents(
          String id) async =>
      {
        for (final entry in cloud.documents.entries)
          if (entry.key.startsWith('clients/$id/financialOperations/'))
            entry.key.split('/').last: entry.value,
      };
}

class _AtomicTransaction implements FinancialTransaction {
  final Map<String, Map<String, dynamic>> documents;
  final writes = <String, Map<String, dynamic>>{};
  _AtomicTransaction(this.documents);
  @override
  Future<Map<String, dynamic>?> read(String path) async =>
      documents[path] == null ? null : Map.from(documents[path]!);
  @override
  void write(String path, Map<String, dynamic> data) => writes[path] = data;
}

void main() {
  late Directory directory;
  late _Cloud cloud;
  late RealtimeSyncService service;
  const invoicePath = 'invoices/sale';
  const historyPath = 'clients/customer/balanceHistory/sale_sale';
  const eventPath = 'clients/customer/financialOperations/operation-1';

  void seedSale({int sequence = 1}) {
    cloud.documents[FinancialCloudUploader.feedHeadPath] = {
      'lastSequence': sequence
    };
    cloud.documents['clients/customer'] = {
      'name': 'Customer',
      'balance': 100.0,
      'financialBaseBalance': 0.0,
      '_version': 1,
    };
    cloud.documents[invoicePath] = {
      'invoiceNumber': 123,
      'clientId': 'customer',
      'clientName': 'Customer',
      'totalSum': 100.0,
      'paidAmount': 0.0,
      'date': DateTime(2026, 10, 1),
      'products': [],
      '_version': 1,
      '_operationId': 'operation-1',
    };
    cloud.documents[historyPath] = {
      'invoiceId': 'sale',
      'invoiceNumber': '123',
      'enteredBalance': 100.0,
      'type': 'sale',
      'timestamp': DateTime(2026, 10, 1),
      '_version': 1,
    };
    cloud.documents[eventPath] = {'delta': 100.0, 'operationId': 'operation-1'};
    cloud.documents['financial_operation_receipts/operation-1'] = {
      'sequence': sequence,
      'operationId': 'operation-1',
      'versions': {'clients/customer': 1, invoicePath: 1, historyPath: 1},
      'customerIds': ['customer'],
      'supplierIds': [],
    };
  }

  Future<void> readyForIncremental() async {
    await appMetaBox.put('financialBaselineVersion', 2);
    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, 0);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('realtime_sync_test_');
    await initHive(directory: directory.path);
    cloud = _Cloud();
    service = RealtimeSyncService(firestore: cloud);
  });
  tearDown(() async {
    await service.stopListening();
    await cloud.receiptStream.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('upgrade repairs an already advanced cursor, invoice and statement',
      () async {
    seedSale(sequence: 4);
    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, 4);
    await service.refreshFromServer();
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(clientsBox.get('customer')!.balance, 100);
    expect(CustomerBalanceStore.balance('customer'), 100);
    expect(appMetaBox.get('financialBaselineVersion'), 2);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 4);
    expect(cloud.reads.every((read) => read.value == Source.server), isTrue);
  });

  for (final warmDevice in [false, true]) {
    test(
        'real 220 sale has identical footer and balance on ${warmDevice ? 'warm' : 'clean'} receiving device',
        () async {
      final receiver = await Directory('${directory.path}/device_b').create();
      if (warmDevice) {
        await Hive.close();
        await initHive(directory: receiver.path);
        await service.refreshFromServer();
        await Hive.close();
        await initHive(directory: directory.path);
      }
      final clientId = await CustomerOperationService.createClient(
          name: 'Two-device customer', openingBalance: 0);
      await CustomerOperationService.saveInvoice({
        'id': 'sale-220',
        'clientId': clientId,
        'clientName': 'Two-device customer',
        'invoiceNumber': 1,
        'date': DateTime(2026, 10, 12),
        'totalSum': 220.0,
        'paidAmount': 0.0,
        'products': [],
      });
      final senderFooter =
          InvoiceFooterData.fromInvoice(invoicesBox.get('sale-220')!.toMap());
      expect(senderFooter.previous, 0);
      expect(senderFooter.remaining, 220);
      await BatchSyncEngine.forTesting(_AtomicCloud(cloud)).processQueue();
      expect(syncQueueBox.isEmpty, isTrue);
      expect(cloud.documents['clients/$clientId']!['balance'], 220);
      await Hive.close();
      await initHive(directory: receiver.path);
      await service.refreshFromServer();
      final received = invoicesBox.get('sale-220')!;
      final footer = InvoiceFooterData.fromInvoice(received.toMap());
      expect(footer.previous, 0);
      expect(footer.total, 220);
      expect(footer.paid, 0);
      expect(footer.remaining, 220);
      expect(clientsBox.get(clientId)!.balance, 220);
      expect(
          CustomerStatementData.financialHistory(clientId).last['balanceAfter'],
          220);
    });
  }

  Future<void> useDevice(String name) async {
    await service.stopListening();
    await Hive.close();
    final device = await Directory('${directory.path}/$name').create();
    await initHive(directory: device.path);
  }

  Map<String, dynamic> scenarioInvoice(
          String clientId, int number, double total, double paid) =>
      {
        'id': 'scenario-$number',
        'clientId': clientId,
        'clientName': 'Three-invoice customer',
        'invoiceNumber': number,
        'date': DateTime(2026, 10, 12, 9 + number),
        'totalSum': total,
        'paidAmount': paid,
        'products': [],
      };

  Future<void> uploadScenario() async {
    await BatchSyncEngine.forTesting(_AtomicCloud(cloud)).processQueue();
    expect(syncQueueBox.values.map((item) => item.lastError), isEmpty);
  }

  Map<String, dynamic> scenarioView(String clientId) {
    final invoices = CustomerStatementData.invoices(clientId)
      ..sort((a, b) =>
          (a['invoiceNumber'] as num).compareTo(b['invoiceNumber'] as num));
    return {
      'balance': CustomerBalanceStore.balance(clientId),
      'customerListBalance': clientsBox.get(clientId)!.balance,
      'cash': boxCacheBox.get('mainBox')?.value ?? 0.0,
      'invoices': invoices.map((invoice) {
        final footer = InvoiceFooterData.fromInvoice(invoice);
        return {
          'id': invoice['id'],
          'number': invoice['invoiceNumber'],
          'previous': footer.previous,
          'total': footer.total,
          'paid': footer.paid,
          'unpaid': footer.total - footer.paid,
          'owed': footer.remaining,
        };
      }).toList(),
      'statement': CustomerStatementData.financialHistory(clientId)
          .map((entry) => {
                'id': entry['id'],
                'invoiceId': entry['invoiceId'],
                'type': entry['type'],
                'amount': entry['enteredBalance'],
                'before': entry['balanceBefore'],
                'after': entry['balanceAfter'],
              })
          .toList(),
    };
  }

  for (final scenario in [
    'both online',
    'receiver offline until after edit',
    'sender queues everything offline, warm receiver',
    'sender queues everything offline, clean receiver',
    'receiver interrupted during edit and restarted',
  ]) {
    test('three invoices and one edit: $scenario', () async {
      final senderOffline = scenario.startsWith('sender queues');
      final receiveEach = scenario == 'both online' ||
          scenario == 'receiver interrupted during edit and restarted';
      if (!scenario.endsWith('clean receiver')) {
        await useDevice('b');
        await service.refreshFromServer();
      }
      await useDevice('a');
      final clientId = await CustomerOperationService.createClient(
          name: 'Three-invoice customer', openingBalance: 0);

      Future<void> publish(double balance) async {
        expect(CustomerBalanceStore.balance(clientId), balance);
        if (senderOffline) return;
        await uploadScenario();
        expect(cloud.documents['clients/$clientId']!['balance'], balance);
        if (receiveEach) {
          await useDevice('b');
          await service.refreshFromServer();
          expect(CustomerBalanceStore.balance(clientId), balance);
          expect(clientsBox.get(clientId)!.balance, balance);
          await useDevice('a');
        }
      }

      await publish(0);
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 1, 220, 0));
      await publish(220);
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 2, 300, 100));
      await publish(420);
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 3, 150, 50));
      await publish(520);
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 2, 350, 120),
          editing: true);
      expect(CustomerBalanceStore.balance(clientId), 550);
      if (senderOffline) expect(syncQueueBox.length, 5);
      final senderView = scenarioView(clientId);
      expect(senderView['cash'], 170);
      expect(
          (senderView['invoices'] as List)
              .map((invoice) => invoice['previous']),
          [0, 220, 450]);
      expect((senderView['invoices'] as List).map((invoice) => invoice['owed']),
          [220, 450, 550]);
      expect((senderView['statement'] as List).length, 5);
      expect((senderView['statement'] as List).last['after'], 550);
      await uploadScenario();
      expect(cloud.documents['clients/$clientId']!['balance'], 550);
      expect(cloud.documents['invoices/scenario-2']!['totalSum'], 350);
      expect(
          cloud.documents['clients/$clientId/invoices/scenario-2']![
              'paidAmount'],
          120);
      expect(cloud.documents['box/mainBox']!['value'], 170);
      await useDevice('b');
      if (scenario == 'receiver interrupted during edit and restarted') {
        cloud.failures.add('clients/$clientId/balanceHistory/scenario-2_sale');
        await expectLater(service.refreshFromServer(), throwsStateError);
        expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 4);
        expect(appMetaBox.get('financialDownloadError'), isNotNull);
        await useDevice('b');
        cloud.failures.clear();
      }
      await service.refreshFromServer();
      expect(scenarioView(clientId), senderView);
      expect(clientsBox.length, 1);
      expect(invoicesBox.length, 3);
      expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 5);
      expect(
          appMetaBox.keys.where((key) =>
              key.toString().startsWith('customerBalanceEvent:$clientId:')),
          hasLength(5));
      expect(appMetaBox.get('financialDownloadError'), isNull);
      await service.refreshFromServer();
      await service.refreshFromServer(repair: true);
      expect(scenarioView(clientId), senderView);
      expect(invoicesBox.length, 3);
      await useDevice('a');
      await service.refreshFromServer();
      expect(scenarioView(clientId), senderView);
    });
  }

  for (final sameInvoice in [false, true]) {
    test(
        'three invoices: concurrent ${sameInvoice ? 'same' : 'different'} invoice edits',
        () async {
      await useDevice('a');
      final clientId = await CustomerOperationService.createClient(
          name: 'Three-invoice customer', openingBalance: 0);
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 1, 220, 0));
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 2, 300, 100));
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 3, 150, 50));
      await uploadScenario();
      await useDevice('b');
      await service.refreshFromServer();
      await CustomerOperationService.saveInvoice(
          sameInvoice
              ? scenarioInvoice(clientId, 2, 400, 100)
              : scenarioInvoice(clientId, 3, 180, 60),
          editing: true);
      await useDevice('a');
      await CustomerOperationService.saveInvoice(
          scenarioInvoice(clientId, 2, 350, 120),
          editing: true);
      await uploadScenario();
      expect(cloud.documents['clients/$clientId']!['balance'], 550);
      expect(cloud.documents['box/mainBox']!['value'], 170);
      await useDevice('b');
      await service.refreshFromServer();
      expect(
          invoicesBox.get(sameInvoice ? 'scenario-2' : 'scenario-3')!.totalSum,
          sameInvoice ? 400 : 180);
      await BatchSyncEngine.forTesting(_AtomicCloud(cloud)).processQueue();
      if (sameInvoice) {
        expect(syncQueueBox.values.single.status, 'failed');
        expect(syncQueueBox.values.single.errorCategory, 'conflict');
        expect(cloud.documents['invoices/scenario-2']!['totalSum'], 350);
        expect(cloud.documents['clients/$clientId']!['balance'], 550);
        expect(cloud.documents['box/mainBox']!['value'], 170);
        expect(invoicesBox.get('scenario-2')!.totalSum, 400);
        expect(
            cloud.documents[FinancialCloudUploader.feedHeadPath]![
                'lastSequence'],
            5);
      } else {
        expect(syncQueueBox.isEmpty, isTrue);
        await service.refreshFromServer();
        final receiverView = scenarioView(clientId);
        expect(receiverView['balance'], 570);
        expect(receiverView['cash'], 180);
        expect((receiverView['statement'] as List).last['after'], 570);
        expect(invoicesBox.length, 3);
        await useDevice('a');
        await service.refreshFromServer();
        expect(scenarioView(clientId), receiverView);
        expect(cloud.documents['clients/$clientId']!['balance'], 570);
        expect(cloud.documents['box/mainBox']!['value'], 180);
      }
    });
  }

  test('invoice deletion removes the payment record on both devices', () async {
    await useDevice('a');
    final clientId = await CustomerOperationService.createClient(
        name: 'Payment customer', openingBalance: 0);
    await CustomerOperationService.saveInvoice({
      'id': 'paid-sale',
      'clientId': clientId,
      'clientName': 'Payment customer',
      'invoiceNumber': 1,
      'date': DateTime.now(),
      'totalSum': 100.0,
      'paidAmount': 20.0,
      'products': [],
    });
    await uploadScenario();
    final payment = PaymentBreakdownLocal(
        id: 'invoice_paid-sale',
        invoiceId: 'paid-sale',
        cash: 20,
        date: DateTime.now(),
        timestamp: DateTime.now());
    final original = {...payment.toFirestore(), '_version': 1};
    cloud.documents['payment_breakdowns/${payment.id}'] = original;
    await PaymentBreakdownRepository.instance.mergeCloud(payment.id, original);
    await useDevice('b');
    await service.refreshFromServer();
    await PaymentBreakdownRepository.instance.mergeCloud(payment.id, original);
    expect(PaymentBreakdownRepository.instance.getAll(), hasLength(1));
    await useDevice('a');
    await CustomerOperationService.deleteInvoice('paid-sale');
    expect(PaymentBreakdownRepository.instance.getAll(), isEmpty);
    await uploadScenario();
    expect(
        cloud.documents['payment_breakdowns/${payment.id}']!['_deleted'], true);
    await useDevice('b');
    await service.refreshFromServer();
    expect(invoicesBox.get('paid-sale'), isNull);
    expect(PaymentBreakdownRepository.instance.box.isEmpty, true);
    expect(CustomerBalanceStore.balance(clientId), 0);
    expect(boxCacheBox.get('mainBox')!.value, 0);
    // Older cached data and unknown legacy document IDs cannot revive it.
    await PaymentBreakdownRepository.instance.mergeCloud(payment.id, original);
    await PaymentBreakdownRepository.instance.mergeCloud('legacy-linked', {
      ...original,
      '_version': 0,
    });
    expect(PaymentBreakdownRepository.instance.box.isEmpty, true);
    await service.refreshFromServer();
    expect(PaymentBreakdownRepository.instance.getAll(), isEmpty);
  });

  test('real supplier creation and purchase hydrate a clean receiver balance',
      () async {
    final id = await SupplierOperationService.createSupplier(
        name: 'Two-device supplier', openingBalance: 0);
    await SupplierOperationService.saveBuyingInvoice({
      'id': 'purchase-220',
      'supplierId': id,
      'invoiceNumber': 1,
      'date': DateTime(2026, 10, 12),
      'totalSum': 330.0,
      'paidAmount': 110.0,
      'products': [],
    });
    await BatchSyncEngine.forTesting(_AtomicCloud(cloud)).processQueue();
    expect(syncQueueBox.isEmpty, isTrue);
    final receiver = await Directory('${directory.path}/device_b').create();
    await Hive.close();
    await initHive(directory: receiver.path);
    await service.refreshFromServer();
    expect(SupplierBalanceStore.balance(id), 220);
    expect(suppliersBox.get(id)!.balance, 220);
    expect(buyingInvoicesBox.get('purchase-220')!.totalSum, 330);
  });

  test('legacy customer and supplier vouchers convert all Firestore timestamps',
      () async {
    seedSale();
    final stamp = Timestamp.fromDate(DateTime(2026, 10, 12));
    for (final collection in ['client_vouchers', 'supplier_vouchers']) {
      cloud.documents['$collection/legacy'] = {
        'date': stamp,
        'timestamp': stamp,
        'createdAt': stamp,
        'amount': 10.0,
        'nested': {
          'times': [stamp]
        },
      };
    }
    await service.refreshFromServer();
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
    for (final key in ['customerVoucher:legacy', 'supplierVoucher:legacy']) {
      final voucher = appMetaBox.get(key) as Map;
      expect(voucher['date'], isA<DateTime>());
      expect(voucher['timestamp'], isA<DateTime>());
      expect(voucher['createdAt'], isA<DateTime>());
      expect(((voucher['nested'] as Map)['times'] as List).single,
          isA<DateTime>());
    }
  });

  test('legacy timestamp operation tags do not block invoice imports',
      () async {
    seedSale();
    cloud.documents[invoicePath]!['_operationId'] =
        Timestamp.fromDate(DateTime(2026, 10, 12));
    await service.refreshFromServer();
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  test(
      'invoice becomes visible only after its customer balance event is imported',
      () async {
    seedSale();
    await readyForIncremental();
    await ClientRepository.instance.mergeCloud('customer', {
      'name': 'Customer',
      'balance': 0.0,
      'financialBaseBalance': 0.0,
      '_version': 0,
    });
    cloud.documents['clients/customer']!
        .addAll({'balance': 220.0, 'financialVersion': 1});
    cloud.documents[invoicePath]!
        .addAll({'totalSum': 220.0, 'previousBalance': 0.0, 'balance': 220.0});
    cloud.documents[eventPath]!['delta'] = 220.0;
    cloud.documents['financial_operation_receipts/operation-1']!['versions'] = {
      invoicePath: 1,
      'clients/customer': 1,
      historyPath: 1,
    };
    final observed = <double>[];
    final subscription = invoicesBox
        .watch()
        .listen((_) => observed.add(CustomerBalanceStore.balance('customer')));
    await service.refreshFromServer();
    await subscription.cancel();
    expect(observed, [220]);
    final footer =
        InvoiceFooterData.fromInvoice(invoicesBox.get('sale')!.toMap());
    expect(footer.previous, 0);
    expect(footer.remaining, 220);
    expect(clientsBox.get('customer')!.balance, 220);
  });

  test('denied collection-group reads still recover a 220 customer balance',
      () async {
    seedSale();
    cloud.documents['clients/customer']!
        .addAll({'balance': 220.0, 'financialVersion': 1});
    cloud.documents[invoicePath]!
        .addAll({'totalSum': 220.0, 'previousBalance': 0.0, 'balance': 220.0});
    cloud.documents[eventPath]!['delta'] = 220.0;
    cloud.documents[historyPath]!['enteredBalance'] = 220.0;
    cloud.permissionFailures
        .addAll(['group:financialOperations', 'group:balanceHistory']);
    await service.refreshFromServer();
    final footer =
        InvoiceFooterData.fromInvoice(invoicesBox.get('sale')!.toMap());
    expect(footer.previous, 0);
    expect(footer.remaining, 220);
    expect(clientsBox.get('customer')!.balance, 220);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  test(
      'balance hydration precedes large invoice reads and resume retains the original head',
      () async {
    seedSale();
    cloud.documents['clients/customer']!
        .addAll({'balance': 220.0, 'financialVersion': 1});
    cloud.documents[invoicePath]!
        .addAll({'totalSum': 220.0, 'previousBalance': 0.0, 'balance': 220.0});
    cloud.documents[eventPath]!['delta'] = 220.0;
    cloud.documents[historyPath]!['enteredBalance'] = 220.0;
    cloud.failures.add('invoices');
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(clientsBox.get('customer')!.balance, 220);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), isNull);
    expect(appMetaBox.get('financialDownloadError'), isNotNull);
    await Hive.close();
    await initHive(directory: directory.path);
    cloud.failures.clear();
    cloud.reads.clear();
    cloud.documents[FinancialCloudUploader.feedHeadPath]!['lastSequence'] = 2;
    cloud.documents['financial_operation_receipts/operation-2'] = {
      'sequence': 2,
      'versions': {},
      'customerIds': [],
      'supplierIds': [],
    };
    await service.refreshFromServer();
    expect(
        cloud.reads.any((entry) => [
              'clients',
              'suppliers',
              'products',
              'group:financialOperations'
            ].contains(entry.key)),
        isFalse);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 2);
    expect(appMetaBox.containsKey('financialBaselineProgress'), isFalse);
    expect(appMetaBox.containsKey('financialDownloadError'), isFalse);
    final footer =
        InvoiceFooterData.fromInvoice(invoicesBox.get('sale')!.toMap());
    expect(footer.previous, 0);
    expect(footer.remaining, 220);
  });

  test(
      'cached bootstrap does not certify the old cursor; online retry repairs it',
      () async {
    seedSale(sequence: 4);
    await appMetaBox.put(HiveMetaKeys.financialChangeSequence, 2);
    cloud.cached.add('group:balanceHistory');
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 2);
    expect(appMetaBox.containsKey('financialBaselineVersion'), isFalse);
    cloud.cached.clear();
    await service.refreshFromServer();
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 4);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(CustomerBalanceStore.balance('customer'), 100);
  });

  test('cached head or pending Firestore writes cannot establish a baseline',
      () async {
    seedSale();
    cloud.cached.add(FinancialCloudUploader.feedHeadPath);
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(
        appMetaBox.containsKey(HiveMetaKeys.financialChangeSequence), isFalse);
    cloud.cached.clear();
    cloud.pendingWrites.add('invoices');
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.containsKey('financialBaselineVersion'), isFalse);
  });

  test(
      'cached invoice cannot advance receipt checkpoint and is imported on retry',
      () async {
    seedSale();
    await readyForIncremental();
    cloud.cached.add(invoicePath);
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    expect(invoicesBox.containsKey('sale'), isFalse);
    cloud.cached.clear();
    await service.refreshFromServer();
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  test('missing document and older version cannot advance the checkpoint',
      () async {
    seedSale();
    await readyForIncremental();
    final invoice = cloud.documents.remove(invoicePath)!;
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    cloud.documents[invoicePath] = {...invoice, '_version': 0};
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    cloud.documents[invoicePath] = {...invoice, '_version': 3};
    await service.refreshFromServer();
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  for (final path in [historyPath, eventPath, 'financial_operation_receipts']) {
    test('cached $path cannot mark a receipt complete', () async {
      seedSale();
      await readyForIncremental();
      cloud.cached.add(path);
      await expectLater(service.refreshFromServer(), throwsStateError);
      expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
      cloud.cached.clear();
      await service.refreshFromServer();
      expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
      expect(balanceHistoryBox.values.single.invoiceId, 'sale');
      expect(CustomerBalanceStore.balance('customer'), 100);
    });
  }

  test('interrupted download retries partial imports without duplicate balance',
      () async {
    seedSale();
    await readyForIncremental();
    cloud.failures.add(historyPath);
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    cloud.failures.clear();
    await service.refreshFromServer();
    expect(balanceHistoryBox.length, 1);
    expect(CustomerBalanceStore.balance('customer'), 100);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  test(
      'missing financial event keeps receipt retryable without double counting',
      () async {
    seedSale();
    await readyForIncremental();
    final event = cloud.documents.remove(eventPath)!;
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    cloud.documents[eventPath] = event;
    await service.refreshFromServer();
    await service.refreshFromServer();
    expect(CustomerBalanceStore.balance('customer'), 100);
    expect(balanceHistoryBox.length, 1);
  });

  test('a missing receipt prevents later receipts from skipping the gap',
      () async {
    seedSale();
    await readyForIncremental();
    cloud.documents['financial_operation_receipts/operation-3'] = {
      'sequence': 3,
      'versions': {},
      'customerIds': [],
      'supplierIds': [],
    };
    await expectLater(service.refreshFromServer(), throwsStateError);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
    cloud.documents['financial_operation_receipts/operation-2'] = {
      'sequence': 2,
      'versions': {},
      'customerIds': [],
      'supplierIds': [],
    };
    await service.refreshFromServer();
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 3);
    expect(CustomerBalanceStore.balance('customer'), 100);
  });

  test('pending edit is preserved and deferred download survives restart',
      () async {
    seedSale();
    await readyForIncremental();
    await invoicesBox.put(
        'sale',
        InvoiceLocal.fromFirestore('sale', {
          ...cloud.documents[invoicePath]!,
          'totalSum': 150.0,
        }));
    await syncQueueBox.put(
        'local-edit',
        SyncQueueItem(
          operationId: 'local-edit',
          operationType: 'editInvoice',
          payloadJson: jsonEncode({
            'financialFormat': 2,
            'cloudWrites': [
              {'path': invoicePath},
              {'path': historyPath},
            ],
            'customerDeltas': {},
            'supplierDeltas': {}
          }),
          createdAt: DateTime(2026, 10, 1),
          status: 'failed',
        ));
    await service.refreshFromServer();
    expect(invoicesBox.get('sale')!.totalSum, 150);
    expect(service.hasDeferredPaths, isTrue);
    expect(balanceHistoryBox.isEmpty, isTrue);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
    cloud.documents['invoices/independent'] = {
      ...cloud.documents[invoicePath]!,
      'totalSum': 80.0,
    };
    cloud.documents['financial_operation_receipts/operation-2'] = {
      'sequence': 2,
      'versions': {'invoices/independent': 1},
      'customerIds': [],
      'supplierIds': [],
    };
    await service.refreshFromServer();
    expect(invoicesBox.get('independent')!.totalSum, 80);
    expect(invoicesBox.get('sale')!.totalSum, 150);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 2);
    await Hive.close();
    await initHive(directory: directory.path);
    expect(service.hasDeferredPaths, isTrue);
    cloud.documents[invoicePath] = {
      ...cloud.documents[invoicePath]!,
      '_version': 2,
      'totalSum': 175.0
    };
    await service.retryDeferredPaths();
    expect(invoicesBox.get('sale')!.totalSum, 150);
    await syncQueueBox.clear();
    await service.retryDeferredPaths();
    expect(invoicesBox.get('sale')!.totalSum, 175);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(service.hasDeferredPaths, isFalse);
  });

  test('repair preserves an accepted opening balance and imported events',
      () async {
    seedSale();
    cloud.documents['clients/customer']!['financialBaseBalance'] = 50.0;
    await service.refreshFromServer();
    expect(CustomerBalanceStore.balance('customer'), 150);
    cloud.documents['clients/customer']!['balance'] = 999.0;
    await service.refreshFromServer(repair: true);
    expect(appMetaBox.get(CustomerBalanceStore.baseKey('customer')), 50);
    expect(CustomerBalanceStore.balance('customer'), 150);
    expect(clientsBox.get('customer')!.balance, 150);
  });

  test(
      'normal refresh is incremental; explicit repair restores skipped legacy sale',
      () async {
    seedSale();
    await service.refreshFromServer();
    cloud.reads.clear();
    await service.refreshFromServer();
    expect(
        cloud.reads.map((read) => read.key), ['financial_operation_receipts']);
    await invoicesBox.delete('sale');
    await balanceHistoryBox.clear();
    await service.refreshFromServer(repair: true);
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(CustomerBalanceStore.balance('customer'), 100);
  });

  test('upload during baseline is caught after the captured head', () async {
    cloud.documents[FinancialCloudUploader.feedHeadPath] = {'lastSequence': 0};
    cloud.afterQuery = (identity) {
      if (identity == 'invoices') {
        cloud.afterQuery = null;
        seedSale();
      }
    };
    await service.refreshFromServer();
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
    expect(CustomerBalanceStore.balance('customer'), 100);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
  });

  test('cache receipt is ignored, metadata-only server confirmation imports it',
      () async {
    await readyForIncremental();
    await service.startListening();
    seedSale();
    final query = _Query(cloud, 'financial_operation_receipts', cursor: 0);
    cloud.receiptStream.add(query.snapshot(cached: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    expect(cloud.includeMetadataChanges, isTrue);
    // docChanges is empty: confirmation must still process snapshot.docs.
    cloud.receiptStream.add(query.snapshot());
    for (var attempt = 0;
        attempt < 100 &&
            appMetaBox.get(HiveMetaKeys.financialChangeSequence) != 1;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
  });

  test('failed listener resumes downloads even with an empty upload queue',
      () async {
    await readyForIncremental();
    await service.startListening();
    seedSale();
    cloud.failures.add(historyPath);
    cloud.receiptStream.add(
        _Query(cloud, 'financial_operation_receipts', cursor: 0).snapshot());
    for (var attempt = 0; attempt < 100 && service.isListening; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(service.isListening, isFalse);
    expect(syncQueueBox.isEmpty, isTrue);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 0);
    cloud.failures.clear();
    await service.startListening();
    expect(service.isListening, isTrue);
    expect(appMetaBox.get(HiveMetaKeys.financialChangeSequence), 1);
    expect(invoicesBox.get('sale')!.totalSum, 100);
    expect(balanceHistoryBox.values.single.invoiceId, 'sale');
  });
}
