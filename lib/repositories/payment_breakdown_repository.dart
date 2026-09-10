import 'dart:async';

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

  /// Saves a legacy unlinked breakdown. New invoice flows should use
  /// [saveForInvoice] so editing an invoice updates the same record.
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

    // 2. Persist the upload operation locally, then sync without blocking UI.
    await _enqueueUpsert(entry);
  }

  PaymentBreakdownLocal? getByInvoiceId(String invoiceId) {
    final normalizedId = invoiceId.trim();
    if (normalizedId.isEmpty) return null;

    PaymentBreakdownLocal? latest;
    for (final entry in box.values) {
      if (entry.invoiceId != normalizedId) continue;
      if (latest == null || entry.timestamp.isAfter(latest.timestamp)) {
        latest = entry;
      }
    }
    return latest;
  }

  /// Creates or replaces the informational payment breakdown for an invoice.
  /// This repository never updates client balances or the cash box.
  Future<void> saveForInvoice({
    required String invoiceId,
    required String invoiceNumber,
    required String clientName,
    required double wallet,
    required double cash,
    required double instapay,
    required double bankTransfer,
    String notes = '',
    DateTime? date,
  }) async {
    final normalizedInvoiceId = invoiceId.trim();
    if (normalizedInvoiceId.isEmpty) return;

    final existing = getByInvoiceId(normalizedInvoiceId);
    final hasAmounts =
        wallet > 0 || cash > 0 || instapay > 0 || bankTransfer > 0;
    if (!hasAmounts) {
      if (existing != null) await deleteBreakdown(existing);
      return;
    }

    final entry = PaymentBreakdownLocal(
      id: existing?.id ?? 'invoice_$normalizedInvoiceId',
      invoiceId: normalizedInvoiceId,
      invoiceNumber: invoiceNumber.trim(),
      clientName: clientName.trim(),
      date: date ?? existing?.date ?? DateTime.now(),
      wallet: wallet,
      cash: cash,
      instapay: instapay,
      bankTransfer: bankTransfer,
      notes: notes,
      timestamp: DateTime.now(),
    );
    await updateBreakdown(entry);
  }

  Future<void> updateBreakdown(PaymentBreakdownLocal entry) async {
    await upsertLocal(entry);
    await _enqueueUpsert(entry);
  }

  Future<void> deleteBreakdown(PaymentBreakdownLocal entry) async {
    await box.delete(entry.id);
    await _enqueueDelete(entry.id);
  }

  /// Queue persistence is also a local Hive write, so invoice saving never
  /// waits for Firestore or network availability.
  Future<void> _enqueueUpsert(PaymentBreakdownLocal entry) async {
    await SyncQueueManager.instance.enqueue(
      operationType: 'upsertPaymentBreakdown',
      payload: {'id': entry.id, 'data': entry.toFirestore()},
    );
    unawaited(ConnectivityService.instance.forceSync());
  }

  Future<void> _enqueueDelete(String id) async {
    await SyncQueueManager.instance.enqueue(
      operationType: 'deletePaymentBreakdown',
      payload: {'id': id},
    );
    unawaited(ConnectivityService.instance.forceSync());
  }

  /// Get all entries for a specific date range
  List<PaymentBreakdownLocal> getByDateRange(DateTime start, DateTime end) {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    return box.values.where((item) {
      return item.date
              .isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
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
