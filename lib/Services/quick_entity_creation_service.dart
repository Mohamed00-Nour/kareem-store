import 'package:uuid/uuid.dart';

import '../local_db/models/balance_history_local.dart';
import '../local_db/models/client_local.dart';
import '../local_db/models/product_local.dart';
import '../local_db/models/supplier_local.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../utils/entity_name_normalizer.dart';

class QuickCreateDuplicateException implements Exception {
  final String existingId;
  final String existingName;

  const QuickCreateDuplicateException(this.existingId, this.existingName);

  @override
  String toString() => 'A record named "$existingName" already exists.';
}

/// Creates invoice-related master data without making a network request.
///
/// Every method writes the entity (and its opening ledger entry, when needed)
/// to Hive first, then appends a durable queue operation. The queue is drained
/// by the connectivity service independently of the invoice screen lifecycle.
class QuickEntityCreationService {
  QuickEntityCreationService._();
  static final QuickEntityCreationService instance =
      QuickEntityCreationService._();

  static const Uuid _uuid = Uuid();

  static void _requireFinite(num value, String fieldName) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, fieldName, 'Value must be finite.');
    }
  }

  Future<ClientLocal> createClient({
    required String name,
    double openingBalance = 0.0,
    String phone = '',
    String address = '',
  }) async {
    _requireFinite(openingBalance, 'openingBalance');
    final displayName = cleanEntityName(name);
    if (displayName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Client name cannot be empty.');
    }

    final existing = ClientRepository.instance.findByName(displayName);
    if (existing != null) {
      throw QuickCreateDuplicateException(existing.id, existing.name);
    }

    final clientId = _uuid.v4();
    final createdAt = DateTime.now();
    final openingHistoryId = '${clientId}_opening';
    final data = <String, dynamic>{
      'id': clientId,
      'clientName': displayName,
      'name': displayName,
      'normalizedName': normalizeEntityName(displayName),
      'balance': openingBalance,
      'openingBalance': openingBalance,
      'phone': phone.trim(),
      'address': address.trim(),
    };

    // Hive is committed before the durable upload is enqueued.
    await ClientRepository.instance.upsertLocal(clientId, data);
    if (openingBalance != 0) {
      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: openingHistoryId,
          parentId: clientId,
          parentType: 'client',
          enteredBalance: openingBalance,
          balanceBefore: 0.0,
          type: 'opening',
          timestamp: createdAt,
          notes: 'رصيد افتتاحي',
        ),
      );
    }

    await SyncQueueManager.instance.enqueue(
      operationType: 'createClient',
      payload: {
        'clientId': clientId,
        'data': data,
        'openingBalance': openingBalance,
        'openingHistoryId': openingHistoryId,
        'createdAt': createdAt,
      },
    );

    return ClientRepository.instance.getById(clientId)!;
  }

  Future<SupplierLocal> createSupplier({
    required String name,
    double openingBalance = 0.0,
    String phone = '',
    String address = '',
  }) async {
    _requireFinite(openingBalance, 'openingBalance');
    final displayName = cleanEntityName(name);
    if (displayName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Supplier name cannot be empty.');
    }

    final existing = SupplierRepository.instance.findByName(displayName);
    if (existing != null) {
      throw QuickCreateDuplicateException(existing.id, existing.name);
    }

    final supplierId = _uuid.v4();
    final createdAt = DateTime.now();
    final openingHistoryId = '${supplierId}_opening';
    final openingVoucherId = '${supplierId}_opening';
    final data = <String, dynamic>{
      'id': supplierId,
      'name': displayName,
      'supplierName': displayName,
      'normalizedName': normalizeEntityName(displayName),
      'balance': openingBalance,
      'totalBalance': openingBalance,
      'openingBalance': openingBalance,
      'phone': phone.trim(),
      'address': address.trim(),
    };

    await SupplierRepository.instance.upsertLocal(supplierId, data);
    if (openingBalance != 0) {
      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: openingHistoryId,
          parentId: supplierId,
          parentType: 'supplier',
          enteredBalance: openingBalance,
          balanceBefore: 0.0,
          type: 'opening',
          timestamp: createdAt,
          direction: 'له',
          notes: 'رصيد افتتاحي',
        ),
      );
    }

    await SyncQueueManager.instance.enqueue(
      operationType: 'createSupplier',
      payload: {
        'supplierId': supplierId,
        'data': data,
        'openingBalance': openingBalance,
        'openingHistoryId': openingHistoryId,
        'openingVoucherId': openingVoucherId,
        'createdAt': createdAt,
      },
    );

    return SupplierRepository.instance.getById(supplierId)!;
  }

  Future<ProductLocal> createProduct({
    required String name,
    required Map<String, dynamic> data,
  }) async {
    final displayName = cleanEntityName(name);
    if (displayName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Product name cannot be empty.');
    }

    final existing = ProductRepository.instance.findByName(displayName);
    if (existing != null) {
      throw QuickCreateDuplicateException(existing.id, existing.name);
    }
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is num) _requireFinite(value, entry.key);
    }

    final productId = _uuid.v4();
    final createdAt = DateTime.now();
    final maxRandom = ProductRepository.instance.getAll().fold<int>(
          0,
          (max, product) =>
              product.randomNumber > max ? product.randomNumber : max,
        );
    final localData = <String, dynamic>{
      ...data,
      'id': productId,
      'name': displayName,
      'normalizedName': normalizeEntityName(displayName),
      'randomNumber': (data['randomNumber'] as num?)?.toInt() ?? maxRandom + 1,
    };

    await ProductRepository.instance.upsertLocal(productId, localData);
    await SyncQueueManager.instance.enqueue(
      operationType: 'createProduct',
      payload: {
        'productId': productId,
        'data': localData,
        'createdAt': createdAt,
      },
    );

    return ProductRepository.instance.getById(productId)!;
  }
}
