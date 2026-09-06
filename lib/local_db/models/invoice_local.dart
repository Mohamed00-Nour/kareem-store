import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'invoice_local.g.dart';

@HiveType(typeId: 4)
class InvoiceLocal extends HiveObject {
  static const _productNumericFields = <String>{
    'amount',
    'quantity',
    'qty',
    'cost',
    'costPrice',
    'selectedPrice',
    'total',
    'totalCost',
    'newCostPrice',
    'newSellingPrice1',
    'newSellingPrice2',
    'newSellingPrice3',
  };

  static double _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0.0;
  }

  static int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? 0;
  }

  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 0)
  int invoiceNumber;

  @HiveField(2, defaultValue: '')
  String clientId;

  @HiveField(3, defaultValue: '')
  String clientName;

  @HiveField(4, defaultValue: '')
  String supplierId;

  @HiveField(5, defaultValue: '')
  String supplierName;

  @HiveField(6)
  DateTime date;

  @HiveField(7, defaultValue: 0.0)
  double totalSum;

  @HiveField(8, defaultValue: 0.0)
  double paidAmount;

  @HiveField(9, defaultValue: 0.0)
  double balance;

  @HiveField(10, defaultValue: 0.0)
  double previousBalance;

  @HiveField(11, defaultValue: 0.0)
  double profitMargin;

  @HiveField(12, defaultValue: 'نقداً')
  String paymentMethod;

  @HiveField(13, defaultValue: '')
  String notes;

  @HiveField(14, defaultValue: 0.0)
  double invoiceDiscount;

  @HiveField(15, defaultValue: 'sale')
  String invoiceType; // 'sale', 'return', 'buying'

  @HiveField(16, defaultValue: false)
  bool isSpecial;

  @HiveField(17, defaultValue: '[]')
  String productsJson;

  @HiveField(18)
  DateTime updatedAt;

  InvoiceLocal({
    required this.id,
    this.invoiceNumber = 0,
    this.clientId = '',
    this.clientName = '',
    this.supplierId = '',
    this.supplierName = '',
    required this.date,
    this.totalSum = 0.0,
    this.paidAmount = 0.0,
    this.balance = 0.0,
    this.previousBalance = 0.0,
    this.profitMargin = 0.0,
    this.paymentMethod = 'نقداً',
    this.notes = '',
    this.invoiceDiscount = 0.0,
    this.invoiceType = 'sale',
    this.isSpecial = false,
    this.productsJson = '[]',
    required this.updatedAt,
  });

  List<Map<String, dynamic>> get products {
    try {
      if (productsJson.isEmpty) return [];
      final decoded = jsonDecode(productsJson);
      if (decoded is List) {
        return decoded.map((e) {
          if (e is! Map) return <String, dynamic>{};
          final product = Map<String, dynamic>.from(e);
          for (final field in _productNumericFields) {
            if (product[field] != null) {
              product[field] = _doubleValue(product[field]);
            }
          }
          return product;
        }).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static String _safeJsonEncode(dynamic data) {
    try {
      return jsonEncode(data, toEncodable: (item) {
        if (item is DateTime) return item.toIso8601String();
        if (item is Timestamp) return item.toDate().toIso8601String();
        return item.toString();
      });
    } catch (_) {
      return '[]';
    }
  }

  set products(List<Map<String, dynamic>> list) {
    productsJson = _safeJsonEncode(list);
  }

  factory InvoiceLocal.fromFirestore(String docId, Map<String, dynamic> data,
      {String defaultType = 'sale'}) {
    DateTime parsedDate;
    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    String pJson = '[]';
    if (data['products'] is List) {
      pJson = _safeJsonEncode(data['products']);
    } else if (data['productsJson'] is String) {
      pJson = data['productsJson'];
    }

    return InvoiceLocal(
      id: docId,
      invoiceNumber: _intValue(data['invoiceNumber']),
      clientId: (data['clientId'] ?? '')?.toString() ?? '',
      clientName: (data['clientName'] ?? '')?.toString() ?? '',
      supplierId: (data['supplierId'] ?? '')?.toString() ?? '',
      supplierName: (data['supplierName'] ?? '')?.toString() ?? '',
      date: parsedDate,
      totalSum: _doubleValue(data['totalSum']),
      paidAmount: _doubleValue(data['paidAmount']),
      balance: _doubleValue(data['balance']),
      previousBalance: _doubleValue(data['previousBalance']),
      profitMargin: _doubleValue(data['profitMargin']),
      paymentMethod: (data['paymentMethod'] ?? 'نقداً')?.toString() ?? 'نقداً',
      notes: (data['notes'] ?? '')?.toString() ?? '',
      invoiceDiscount: _doubleValue(data['invoiceDiscount']),
      invoiceType:
          (data['invoiceType'] ?? defaultType)?.toString() ?? defaultType,
      isSpecial: data['isSpecial'] == true,
      productsJson: pJson,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'clientId': clientId,
      'clientName': clientName,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'date': date,
      'totalSum': totalSum,
      'paidAmount': paidAmount,
      'balance': balance,
      'previousBalance': previousBalance,
      'profitMargin': profitMargin,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': invoiceDiscount,
      'invoiceType': invoiceType,
      'isSpecial': isSpecial,
      'products': products,
    };
  }
}
