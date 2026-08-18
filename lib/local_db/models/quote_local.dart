import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'quote_local.g.dart';

@HiveType(typeId: 6)
class QuoteLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String clientName;

  @HiveField(2)
  String clientId;

  @HiveField(3)
  DateTime date;

  @HiveField(4)
  double totalSum;

  @HiveField(5)
  double paidAmount;

  @HiveField(6)
  String paymentMethod;

  @HiveField(7)
  String notes;

  @HiveField(8)
  double invoiceDiscount;

  @HiveField(9)
  bool discountIsPercent;

  @HiveField(10)
  String productsJson;

  @HiveField(11)
  DateTime createdAt;

  QuoteLocal({
    required this.id,
    this.clientName = '',
    this.clientId = '',
    required this.date,
    this.totalSum = 0.0,
    this.paidAmount = 0.0,
    this.paymentMethod = 'نقداً',
    this.notes = '',
    this.invoiceDiscount = 0.0,
    this.discountIsPercent = false,
    this.productsJson = '[]',
    required this.createdAt,
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

  factory QuoteLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    DateTime parsedDate;
    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else {
      parsedDate = DateTime.now();
    }

    String pJson = '[]';
    if (data['products'] is List) {
      pJson = _safeJsonEncode(data['products']);
    } else if (data['productsJson'] is String) {
      pJson = data['productsJson'];
    }


    return QuoteLocal(
      id: docId,
      clientName: (data['clientName'] ?? '')?.toString() ?? '',
      clientId: (data['clientId'] ?? '')?.toString() ?? '',
      date: parsedDate,
      totalSum: (data['totalSum'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (data['paymentMethod'] ?? 'نقداً')?.toString() ?? 'نقداً',
      notes: (data['notes'] ?? '')?.toString() ?? '',
      invoiceDiscount: (data['invoiceDiscount'] as num?)?.toDouble() ?? 0.0,
      discountIsPercent: data['discountIsPercent'] == true,
      productsJson: pJson,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientName': clientName,
      'clientId': clientId,
      'date': date,
      'totalSum': totalSum,
      'paidAmount': paidAmount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'invoiceDiscount': invoiceDiscount,
      'discountIsPercent': discountIsPercent,
      'products': products,
    };
  }
}
