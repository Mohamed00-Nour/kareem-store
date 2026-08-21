import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'balance_history_local.g.dart';

@HiveType(typeId: 8)
class BalanceHistoryLocal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: '')
  String parentId; // clientId or supplierId

  @HiveField(2, defaultValue: '')
  String parentType; // 'client' or 'supplier'

  @HiveField(3, defaultValue: 0.0)
  double enteredBalance;

  @HiveField(4, defaultValue: 0.0)
  double balanceBefore;

  @HiveField(5, defaultValue: '')
  String type; // 'sale', 'sale_payment', 'return', 'return_payment', 'addition', 'deduction', 'opening'

  @HiveField(6, defaultValue: '')
  String invoiceId;

  @HiveField(7, defaultValue: '')
  String invoiceNumber;

  @HiveField(8)
  DateTime timestamp;

  @HiveField(9, defaultValue: '')
  String direction; // 'له' or 'عليه' for suppliers

  @HiveField(10, defaultValue: '')
  String notes;

  BalanceHistoryLocal({
    required this.id,
    required this.parentId,
    required this.parentType,
    this.enteredBalance = 0.0,
    this.balanceBefore = 0.0,
    this.type = '',
    this.invoiceId = '',
    this.invoiceNumber = '',
    required this.timestamp,
    this.direction = '',
    this.notes = '',
  });

  factory BalanceHistoryLocal.fromFirestore(
    String docId,
    String parentId,
    String parentType,
    Map<String, dynamic> data,
  ) {
    DateTime parsedTime;
    final ts = data['timestamp'];
    final date = data['date'];
    if (ts is Timestamp) {
      parsedTime = ts.toDate();
    } else if (date is Timestamp) {
      parsedTime = date.toDate();
    } else if (date is DateTime) {
      parsedTime = date;
    } else {
      parsedTime = DateTime.now();
    }

    final rawEntered = data['enteredBalance'] ?? data['amount'] ?? data['value'];
    double entered = 0.0;
    if (rawEntered is num) {
      entered = rawEntered.toDouble();
    } else if (rawEntered is String) {
      entered = double.tryParse(rawEntered) ?? 0.0;
    }

    final rawBefore = data['balanceBefore'];
    double before = 0.0;
    if (rawBefore is num) {
      before = rawBefore.toDouble();
    } else if (rawBefore is String) {
      before = double.tryParse(rawBefore) ?? 0.0;
    }

    return BalanceHistoryLocal(
      id: docId,
      parentId: parentId,
      parentType: parentType,
      enteredBalance: entered,
      balanceBefore: before,
      type: (data['type'] ?? '')?.toString() ?? '',
      invoiceId: (data['invoiceId'] ?? '')?.toString() ?? '',
      invoiceNumber: (data['invoiceNumber'] ?? '')?.toString() ?? '',
      timestamp: parsedTime,
      direction: (data['direction'] ?? '')?.toString() ?? '',
      notes: (data['notes'] ?? data['description'] ?? '')?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'enteredBalance': enteredBalance,
      'balanceBefore': balanceBefore,
      'type': type,
      'invoiceId': invoiceId,
      'invoiceNumber': invoiceNumber,
      'timestamp': timestamp,
      if (direction.isNotEmpty) 'direction': direction,
      if (notes.isNotEmpty) 'notes': notes,
    };
  }
}
