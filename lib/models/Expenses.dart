import 'package:cloud_firestore/cloud_firestore.dart';

class Expenses {
  String id;
  String category;
  String date;
  String value;
  String notes;
  Map<String, String> attributes;
  final Timestamp? time;
  final Timestamp? dateTimestamp;

  /// Legacy field; kept for older documents.
  String get name => category;

  Expenses({
    required this.id,
    required this.category,
    required this.date,
    required this.value,
    this.notes = '',
    this.attributes = const {},
    this.time,
    this.dateTimestamp,
  });

  factory Expenses.fromMap(Map<String, dynamic> data, {String? id}) {
    final rawAttrs = data['attributes'];
    final Map<String, String> attrs = {};
    if (rawAttrs is Map) {
      rawAttrs.forEach((k, v) {
        attrs[k.toString()] = v?.toString() ?? '';
      });
    }

    final category = (data['category'] ?? data['name'] ?? '').toString();

    return Expenses(
      id: id ?? data['id']?.toString() ?? '',
      category: category,
      date: data['date']?.toString() ?? '',
      value: data['value']?.toString() ?? '',
      notes: data['notes']?.toString() ?? '',
      attributes: attrs,
      time: data['time'] as Timestamp?,
      dateTimestamp: data['dateTimestamp'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': category,
      'date': date,
      'value': value,
      'notes': notes,
      'attributes': attributes,
      if (dateTimestamp != null) 'dateTimestamp': dateTimestamp,
      'time': time,
    };
  }

  double get amount =>
      double.tryParse(value.replaceAll(',', '')) ?? 0.0;
}
