import 'package:hive/hive.dart';

part 'payment_breakdown_local.g.dart';

@HiveType(typeId: 10)
class PaymentBreakdownLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2, defaultValue: 0.0)
  double wallet; // محفظة

  @HiveField(3, defaultValue: 0.0)
  double cash; // نقدي

  @HiveField(4, defaultValue: 0.0)
  double instapay; // أنستاباي

  @HiveField(5, defaultValue: 0.0)
  double bankTransfer; // تحويل بنكي

  @HiveField(6, defaultValue: '')
  String notes;

  @HiveField(7)
  DateTime timestamp;

  PaymentBreakdownLocal({
    required this.id,
    required this.date,
    this.wallet = 0.0,
    this.cash = 0.0,
    this.instapay = 0.0,
    this.bankTransfer = 0.0,
    this.notes = '',
    required this.timestamp,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'wallet': wallet,
      'cash': cash,
      'instapay': instapay,
      'bankTransfer': bankTransfer,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PaymentBreakdownLocal.fromFirestore(
      String docId, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PaymentBreakdownLocal(
      id: docId,
      date: parseDate(data['date']),
      wallet: (data['wallet'] as num?)?.toDouble() ?? 0.0,
      cash: (data['cash'] as num?)?.toDouble() ?? 0.0,
      instapay: (data['instapay'] as num?)?.toDouble() ?? 0.0,
      bankTransfer: (data['bankTransfer'] as num?)?.toDouble() ?? 0.0,
      notes: (data['notes'] ?? '').toString(),
      timestamp: parseDate(data['timestamp']),
    );
  }
}
