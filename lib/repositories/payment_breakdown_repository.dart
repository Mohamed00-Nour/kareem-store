import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../local_db/models/payment_breakdown_local.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_queue_manager.dart';

class PaymentBreakdownRepository {
  PaymentBreakdownRepository._internal();
  static final PaymentBreakdownRepository instance =
      PaymentBreakdownRepository._internal();

  static const String boxName = 'paymentBreakdownsBox';

  Box<PaymentBreakdownLocal>? _box;

  Box<PaymentBreakdownLocal> get box {
    if (_box == null || !_box!.isOpen) {
      _box = Hive.box<PaymentBreakdownLocal>(boxName);
    }
    return _box!;
  }

  static Future<void> init() async {
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(PaymentBreakdownLocalAdapter());
    }
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<PaymentBreakdownLocal>(boxName);
    }
  }

  /// Upsert local entry in 0ms (Hive primary DB)
  Future<void> upsertLocal(PaymentBreakdownLocal entry) async {
    await box.put(entry.id, entry);
  }

  /// Save breakdown: Hive first (0ms), then background sync to Firestore
  Future<void> saveBreakdown({
    required double wallet,
    required double cash,
    required double instapay,
    required double bankTransfer,
    String notes = '',
    DateTime? date,
  }) async {
    if (wallet <= 0 && cash <= 0 && instapay <= 0 && bankTransfer <= 0) {
      return;
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final entryDate = date ?? DateTime.now();

    final entry = PaymentBreakdownLocal(
      id: id,
      date: entryDate,
      wallet: wallet,
      cash: cash,
      instapay: instapay,
      bankTransfer: bankTransfer,
      notes: notes,
      timestamp: DateTime.now(),
    );

    // 1. Save to local Hive (0ms)
    await upsertLocal(entry);

    // 2. Background sync to Firestore
    _syncToFirestore(entry);
  }

  void _syncToFirestore(PaymentBreakdownLocal entry) async {
    try {
      final payload = entry.toFirestore();
      if (!ConnectivityService.instance.isOnline) {
        await SyncQueueManager.instance.enqueue(
          operationType: 'createPaymentBreakdown',
          payload: {'id': entry.id, 'data': payload},
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('payment_breakdowns')
          .doc(entry.id)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing payment breakdown to Firestore: $e');
    }
  }

  /// Get all entries for a specific date range
  List<PaymentBreakdownLocal> getByDateRange(DateTime start, DateTime end) {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    return box.values.where((item) {
      return item.date.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
          item.date.isBefore(endOfDay.add(const Duration(seconds: 1)));
    }).toList();
  }

  /// Fetch all entries from local Hive
  List<PaymentBreakdownLocal> getAll() {
    return box.values.toList();
  }

  /// Full background sync from Firestore into Hive
  Future<void> fullSyncFromFirestore() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payment_breakdowns')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final local = PaymentBreakdownLocal.fromFirestore(doc.id, data);
        await upsertLocal(local);
      }
    } catch (e) {
      debugPrint('Error fetching payment breakdowns from Firestore: $e');
    }
  }
}
