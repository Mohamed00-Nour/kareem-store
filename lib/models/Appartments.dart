import 'package:cloud_firestore/cloud_firestore.dart';

class Appartments {
  String id;
  String name;
  String date;
  String value;
  final Timestamp time;

  Appartments({required this.id, required this.name, required this.date, required this.value , required this.time});

  factory Appartments.fromMap(Map<String, dynamic> data) {
    return Appartments(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      date: data['date'] ?? '',
      value: data['value'] ?? '',
      time: data['time'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date,
      'value': value,
      'time': time,
    };
  }
}