import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'expense_local.g.dart';

@HiveType(typeId: 5)
class ExpenseLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String category;

  @HiveField(2, defaultValue: 0.0)
  double amount;

  @HiveField(3)
  DateTime date;

  @HiveField(4, defaultValue: '')
  String notes;

  @HiveField(5)
  String attributesJson;

  @HiveField(6)
  DateTime updatedAt;

  ExpenseLocal({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.notes = '',
    this.attributesJson = '{}',
    required this.updatedAt,
  });

  Map<String, String> get attributes {
    try {
      if (attributesJson.isEmpty) return {};
      final decoded = jsonDecode(attributesJson);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  set attributes(Map<String, String> map) {
    attributesJson = jsonEncode(map);
  }

  factory ExpenseLocal.fromFirestore(String docId, Map<String, dynamic> data) {
    DateTime parsedDate;
    final dateTs = data['dateTimestamp'];
    final timeTs = data['time'];
    final rawDate = data['date'];

    if (dateTs is Timestamp) {
      parsedDate = dateTs.toDate();
    } else if (timeTs is Timestamp) {
      parsedDate = timeTs.toDate();
    } else if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String && rawDate.isNotEmpty) {
      final part = rawDate.split(' ').first;
      parsedDate = DateTime.tryParse(part) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    final rawVal = data['value'];
    double parsedAmount = 0.0;
    if (rawVal is num) {
      parsedAmount = rawVal.toDouble();
    } else if (rawVal is String) {
      parsedAmount = double.tryParse(rawVal.replaceAll(',', '')) ?? 0.0;
    }

    String attrJson = '{}';
    if (data['attributes'] is Map) {
      attrJson = jsonEncode(data['attributes']);
    }

    return ExpenseLocal(
      id: docId,
      category: (data['category'] ?? data['name'])?.toString().trim() ?? '',
      amount: parsedAmount,
      date: parsedDate,
      notes: (data['notes'] ?? '')?.toString().trim() ?? '',
      attributesJson: attrJson,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': category,
      'value': amount.toString(),
      'notes': notes,
      'attributes': attributes,
      'date': date.toIso8601String().split('T').first,
      'dateTimestamp': Timestamp.fromDate(date),
    };
  }
}
