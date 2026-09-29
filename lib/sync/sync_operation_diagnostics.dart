import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';

import '../local_db/models/sync_queue_item.dart';

class SyncErrorCategories {
  SyncErrorCategories._();
  static const transient = 'transient';
  static const quota = 'quota';
  static const authentication = 'authentication';
  static const permission = 'permission';
  static const validation = 'validation';
  static const conflict = 'conflict';
  static const legacy = 'legacy';
  static const unknown = 'unknown';

  static bool canRetry(String? category) =>
      category == null ||
      category == transient ||
      category == quota ||
      category == unknown;

  static bool canRetryAutomatically(String? category) =>
      category == null || category == transient || category == unknown;
}

class SyncFailureDetails {
  final String category;
  final String code;
  final String technicalMessage;
  final String userMessageAr;

  const SyncFailureDetails({
    required this.category,
    required this.code,
    required this.technicalMessage,
    required this.userMessageAr,
  });

  bool get canRetry => SyncErrorCategories.canRetry(category);
  bool get canRetryAutomatically =>
      SyncErrorCategories.canRetryAutomatically(category);
}

class SyncFailureClassifier {
  SyncFailureClassifier._();
  static SyncFailureDetails classify(Object error) {
    final technical = error.toString();
    final lower = technical.toLowerCase();
    final firebaseCode = error is FirebaseException ? error.code : '';

    if (lower.contains('legacy financial operation')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.legacy,
        code: 'legacy-financial-operation',
        technicalMessage: technical,
        userMessageAr:
            'عملية قديمة تحتاج مراجعة قبل الرفع لحماية الرصيد والمخزون من التكرار.',
      );
    }

    if (firebaseCode == 'unauthenticated' ||
        lower.contains('unauthenticated') ||
        lower.contains('not authenticated')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.authentication,
        code: firebaseCode.isEmpty ? 'unauthenticated' : firebaseCode,
        technicalMessage: technical,
        userMessageAr: 'انتهت جلسة تسجيل الدخول. سجّل الدخول ثم أعد المحاولة.',
      );
    }

    if (firebaseCode == 'permission-denied' ||
        lower.contains('permission-denied') ||
        lower.contains('permission denied')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.permission,
        code: firebaseCode.isEmpty ? 'permission-denied' : firebaseCode,
        technicalMessage: technical,
        userMessageAr: 'لا توجد صلاحية لرفع هذه العملية. راجع حساب المستخدم.',
      );
    }

    if (lower.contains('concurrent change') ||
        lower.contains('historical ') ||
        lower.contains('invoice lines or customer changed') ||
        lower.contains('record already exists') ||
        lower.contains('record missing or deleted') ||
        lower.contains('review before retrying')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.conflict,
        code: 'cloud-conflict',
        technicalMessage: technical,
        userMessageAr:
            'توجد بيانات مختلفة على جهاز آخر أو على الخادم. راجع النسختين قبل المتابعة.',
      );
    }

    if (lower.contains('product missing') ||
        lower.contains('customer missing') ||
        lower.contains('supplier missing') ||
        lower.contains('archived') ||
        lower.contains('invalid ') ||
        lower.contains('must be cached') ||
        lower.contains('atomic upload limit')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.validation,
        code: 'invalid-operation-data',
        technicalMessage: technical,
        userMessageAr:
            'بيانات العملية غير مكتملة أو غير صالحة. افتح التفاصيل لمعرفة السجل المطلوب.',
      );
    }

    if (firebaseCode == 'resource-exhausted' ||
        lower.contains('resource-exhausted') ||
        lower.contains('resource exhausted')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.quota,
        code: 'resource-exhausted',
        technicalMessage: technical,
        userMessageAr:
            'توقّف الرفع لأن حصة Firebase المتاحة قد نفدت أو لأن الخدمة تحت ضغط. '
            'العملية محفوظة على الجهاز ولن تضيع. انتظر تجدد الحصة أو راجع خطة Firebase، ثم اضغط إعادة المحاولة.',
      );
    }

    const transientCodes = {
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'internal',
      'network-request-failed',
      'unavailable',
      'unknown',
    };
    if (transientCodes.contains(firebaseCode) ||
        lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('unavailable') ||
        lower.contains('connection')) {
      return SyncFailureDetails(
        category: SyncErrorCategories.transient,
        code: firebaseCode.isEmpty ? 'temporary-upload-failure' : firebaseCode,
        technicalMessage: technical,
        userMessageAr:
            'تعذر الاتصال بالخادم مؤقتاً. ستتم إعادة المحاولة تلقائياً.',
      );
    }

    return SyncFailureDetails(
      category: SyncErrorCategories.unknown,
      code: firebaseCode.isEmpty ? 'unknown' : firebaseCode,
      technicalMessage: technical,
      userMessageAr:
          'تعذر رفع العملية. احتفظ بها وافتح التفاصيل قبل تكرار إدخالها.',
    );
  }

  static String inferCategory(String? message) {
    if (message == null || message.trim().isEmpty) {
      return SyncErrorCategories.unknown;
    }
    return classify(message).category;
  }
}

class SyncOperationDiagnostics {
  final String operationId;
  final String operationType;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? partyId;
  final String? partyName;
  final String? partyType;
  final double? amount;
  final List<String> resourceKeys;

  const SyncOperationDiagnostics({
    required this.operationId,
    required this.operationType,
    this.invoiceId,
    this.invoiceNumber,
    this.partyId,
    this.partyName,
    this.partyType,
    this.amount,
    this.resourceKeys = const [],
  });

  factory SyncOperationDiagnostics.fromItem(SyncQueueItem item) {
    final stored = item.diagnosticsJson;
    if (stored != null && stored.isNotEmpty) {
      try {
        return SyncOperationDiagnostics.fromMap(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        );
      } catch (_) {
        // Fall through and rebuild metadata from the immutable payload.
      }
    }
    Map<String, dynamic> payload = const {};
    try {
      payload = Map<String, dynamic>.from(jsonDecode(item.payloadJson) as Map);
    } catch (_) {}
    return SyncOperationDiagnostics.fromPayload(
      item.operationId,
      item.operationType,
      payload,
    );
  }

  factory SyncOperationDiagnostics.fromPayload(
    String operationId,
    String operationType,
    Map<String, dynamic> payload,
  ) {
    final invoice = _invoiceData(payload);
    final party = _partyData(payload);
    final invoiceId = _firstText([
      payload['invoiceId'],
      invoice == null ? null : invoice['invoiceId'],
      invoice == null ? null : invoice['id'],
    ]);
    final invoiceNumber = _firstText([
      payload['invoiceNumber'],
      invoice == null ? null : invoice['invoiceNumber'],
    ]);
    final explicitClientId = _firstText([
      payload['clientId'],
      invoice == null ? null : invoice['clientId'],
      party == null ? null : party['clientId'],
    ]);
    final explicitSupplierId = _firstText([
      payload['supplierId'],
      invoice == null ? null : invoice['supplierId'],
      party == null ? null : party['supplierId'],
    ]);
    final isSupplier = explicitSupplierId != null ||
        operationType.toLowerCase().contains('supplier') ||
        operationType.toLowerCase().contains('buying');
    final partyRecordId = party == null ? null : _nullableText(party['id']);
    final clientId = explicitClientId ?? (isSupplier ? null : partyRecordId);
    final supplierId =
        explicitSupplierId ?? (isSupplier ? partyRecordId : null);
    final partyId = isSupplier ? supplierId : clientId;
    final partyName = _firstText([
      invoice == null
          ? null
          : invoice[isSupplier ? 'supplierName' : 'clientName'],
      party == null ? null : party[isSupplier ? 'supplierName' : 'clientName'],
      party == null ? null : party['name'],
      payload[isSupplier ? 'supplierName' : 'clientName'],
    ]);
    final amount = _firstNumber([
      invoice == null ? null : invoice['totalSum'],
      payload['totalSum'],
      payload['amount'],
      payload['openingBalance'],
    ]);

    final resources = <String>{};
    final cloudWrites = payload['cloudWrites'];
    if (cloudWrites is List) {
      for (final raw in cloudWrites) {
        if (raw is! Map) continue;
        final path = raw['path']?.toString() ?? '';
        final key = resourceKeyForPath(path);
        if (key != null) resources.add(key);
      }
    }
    if (clientId != null) resources.add('clients/$clientId');
    if (supplierId != null) resources.add('suppliers/$supplierId');
    if (invoiceId != null) resources.add('invoice/$invoiceId');
    final productId = _firstText([payload['productId'], payload['id']]);
    if (operationType.toLowerCase().contains('product') && productId != null) {
      resources.add('products/$productId');
    }
    if (operationType == 'updateBox') resources.add('box/mainBox');
    if (payload['financialFormat'] != 2 &&
        const {
          'createClient',
          'createInvoice',
          'editInvoice',
          'deleteInvoice',
          'createReturn',
          'deleteReturn',
          'deleteReturnInvoice',
          'adjustClientBalance',
          'updateBox',
          'createSupplier',
          'createBuyingInvoice',
          'editBuyingInvoice',
          'deleteBuyingInvoice',
          'adjustSupplierBalance',
        }.contains(operationType)) {
      // Old financial payloads do not describe every stock/cash dependency.
      // Keep them as a global barrier until they receive explicit review.
      resources.add('*');
    }
    if (resources.isEmpty) resources.add('*');

    return SyncOperationDiagnostics(
      operationId: operationId,
      operationType: operationType,
      invoiceId: invoiceId,
      invoiceNumber: invoiceNumber,
      partyId: partyId,
      partyName: partyName,
      partyType: partyId == null ? null : (isSupplier ? 'supplier' : 'client'),
      amount: amount,
      resourceKeys: resources.toList()..sort(),
    );
  }

  factory SyncOperationDiagnostics.fromMap(Map<String, dynamic> map) =>
      SyncOperationDiagnostics(
        operationId: map['operationId']?.toString() ?? '',
        operationType: map['operationType']?.toString() ?? '',
        invoiceId: _nullableText(map['invoiceId']),
        invoiceNumber: _nullableText(map['invoiceNumber']),
        partyId: _nullableText(map['partyId']),
        partyName: _nullableText(map['partyName']),
        partyType: _nullableText(map['partyType']),
        amount: _number(map['amount']),
        resourceKeys: (map['resourceKeys'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'operationId': operationId,
        'operationType': operationType,
        if (invoiceId != null) 'invoiceId': invoiceId,
        if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
        if (partyId != null) 'partyId': partyId,
        if (partyName != null) 'partyName': partyName,
        if (partyType != null) 'partyType': partyType,
        if (amount != null) 'amount': amount,
        'resourceKeys': resourceKeys,
      };

  String toJson() => jsonEncode(toMap());

  static bool sharesResources(
      SyncOperationDiagnostics first, SyncOperationDiagnostics second) {
    if (first.resourceKeys.contains('*') || second.resourceKeys.contains('*')) {
      return true;
    }
    final keys = first.resourceKeys.toSet();
    return second.resourceKeys.any(keys.contains);
  }

  static String? resourceKeyForPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    return '${parts[0]}/${parts[1]}';
  }

  static Map<String, dynamic>? _invoiceData(Map<String, dynamic> payload) {
    for (final key in const ['invoiceData', 'data']) {
      final value = payload[key];
      if (value is Map &&
          (value.containsKey('invoiceNumber') ||
              value.containsKey('products') ||
              value.containsKey('totalSum'))) {
        return Map<String, dynamic>.from(value);
      }
    }
    final writes = payload['localWrites'];
    if (writes is List) {
      for (final raw in writes) {
        if (raw is! Map) continue;
        final box = raw['box']?.toString().toLowerCase() ?? '';
        final value = raw['data'];
        if (box.contains('invoice') && value is Map) {
          return Map<String, dynamic>.from(value);
        }
      }
    }
    return null;
  }

  static Map<String, dynamic>? _partyData(Map<String, dynamic> payload) {
    final writes = payload['localWrites'];
    if (writes is List) {
      for (final raw in writes) {
        if (raw is! Map || raw['data'] is! Map) continue;
        final box = raw['box']?.toString().toLowerCase() ?? '';
        if (box.contains('client') || box.contains('supplier')) {
          return Map<String, dynamic>.from(raw['data'] as Map);
        }
      }
    }
    return null;
  }

  static String? _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = _nullableText(value);
      if (text != null) return text;
    }
    return null;
  }

  static double? _firstNumber(List<dynamic> values) {
    for (final value in values) {
      final number = _number(value);
      if (number != null) return number;
    }
    return null;
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '') ?? '');
  }
}
