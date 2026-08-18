import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'invoice_local.g.dart';

@HiveType(typeId: 4)
class InvoiceLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  int invoiceNumber;

  @HiveField(2)
  String clientId;

  @HiveField(3)
  String clientName;

  @HiveField(4)
  String supplierId;

  @HiveField(5)
  String supplierName;

  @HiveField(6)
  DateTime date;

  @HiveField(7)
  double totalSum;

  @HiveField(8)
  double paidAmount;

  @HiveField(9)
  double balance;

  @HiveField(10)
  double previousBalance;

  @HiveField(11)
  double profitMargin;

  @HiveField(12)
  String paymentMethod;

  @HiveField(13)
  String notes;

  @HiveField(14)
  double invoiceDiscount;

  @HiveField(15)
  String invoiceType; // 'sale', 'return', 'buying'

  @HiveField(16)
  bool isSpecial;

  @HiveField(17)
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
        return decoded
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
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

  factory InvoiceLocal.fromFirestore(String docId, Map<String, dynamic> data, {String defaultType = 'sale'}) {
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
      invoiceNumber: (data['invoiceNumber'] as num?)?.toInt() ?? 0,
      clientId: (data['clientId'] ?? '')?.toString() ?? '',
      clientName: (data['clientName'] ?? '')?.toString() ?? '',
      supplierId: (data['supplierId'] ?? '')?.toString() ?? '',
      supplierName: (data['supplierName'] ?? '')?.toString() ?? '',
      date: parsedDate,
      totalSum: (data['totalSum'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0.0,
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      previousBalance: (data['previousBalance'] as num?)?.toDouble() ?? 0.0,
      profitMargin: (data['profitMargin'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (data['paymentMethod'] ?? 'نقداً')?.toString() ?? 'نقداً',
      notes: (data['notes'] ?? '')?.toString() ?? '',
      invoiceDiscount: (data['invoiceDiscount'] as num?)?.toDouble() ?? 0.0,
      invoiceType: (data['invoiceType'] ?? defaultType)?.toString() ?? defaultType,
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
