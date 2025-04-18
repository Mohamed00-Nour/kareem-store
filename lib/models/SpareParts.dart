class SpareParts {
  String id;
  String name;
  String date;
  String value;
  double amount;
  SpareParts({required this.id, required this.name, required this.date, required this.value , required this.amount});

  factory SpareParts.fromMap(Map<String, dynamic> data) {
    return SpareParts(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      date: data['date'] ?? '',
      value: data['value'] ?? '',
      amount: data['amount'] ?? 0,

    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date,
      'value': value,
      'amount': amount,
    };
  }
}