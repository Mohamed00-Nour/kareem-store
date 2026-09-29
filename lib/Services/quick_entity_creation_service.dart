import 'package:uuid/uuid.dart';

import '../local_db/models/client_local.dart';
import '../local_db/models/product_local.dart';
import '../local_db/models/supplier_local.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../sync/sync_queue_manager.dart';
import '../utils/entity_name_normalizer.dart';
import 'customer_operation_service.dart';
import 'supplier_operation_service.dart';

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

    final clientId = await CustomerOperationService.createClient(
        name: displayName,
        openingBalance: openingBalance,
        phone: phone,
        address: address);
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

    final supplierId = await SupplierOperationService.createSupplier(
      name: displayName,
      openingBalance: openingBalance,
      phone: phone.trim(),
      address: address.trim(),
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
