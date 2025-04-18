import 'package:cloud_firestore/cloud_firestore.dart';

class Expenses {
  String id;
  String name;
  String date;
  String value;
  final Timestamp? time; // Make the time field optional

  Expenses({required this.id, required this.name, required this.date, required this.value, this.time});

  factory Expenses.fromMap(Map<String, dynamic> data) {
    return Expenses(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      date: data['date'] ?? '',
      value: data['value'] ?? '',
      time: data['time'] as Timestamp?, // Cast to Timestamp?
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date,
      'value': value,
      'time': time, // Include the time field
    };
  }
}