import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../local_db/hive_init.dart';
import 'connectivity_service.dart';

/// Result of trying to open an invoice for editing.
class InvoiceEditLockResult {
  /// False when another device is editing this invoice right now.
  final bool allowed;

  /// Email of the user holding the lock, when [allowed] is false.
  final String? lockedBy;

  const InvoiceEditLockResult.allowed()
      : allowed = true,
        lockedBy = null;
  const InvoiceEditLockResult.blocked(this.lockedBy) : allowed = false;
}

/// Short-lived cloud lock that stops two devices from editing the same
/// invoice at once.
///
/// The lock only works online. When the cloud cannot be reached the edit is
/// allowed: the save-time check and the sync conflict choices still protect
/// the invoice. A lock is renewed while the edit page is open and expires on
/// its own [ttl] after the page closes or the app is killed.
class InvoiceEditLock {
  static const ttl = Duration(minutes: 3);
  static const _renewEvery = Duration(seconds: 60);
  static const _collection = 'invoice_edit_locks';
  static const _deviceKey = 'invoiceEditLockDeviceId';

  /// Cloud path of the invoice, e.g. `invoices/abc` or `buying invoices/abc`.
  final String invoicePath;
  final FirebaseFirestore? _firestore;
  Timer? _renewTimer;
  bool _held = false;

  InvoiceEditLock(this.invoicePath, {FirebaseFirestore? firestore})
      : _firestore = firestore;

  FirebaseFirestore get _fs => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _ref => _fs
      .collection(_collection)
      .doc(invoicePath.replaceAll('/', '__').replaceAll(' ', '_'));

  /// Stable id of this installation, so the same user on two phones still
  /// counts as two editors.
  static String deviceId() {
    final existing = appMetaBox.get(_deviceKey)?.toString() ?? '';
    if (existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    appMetaBox.put(_deviceKey, created);
    return created;
  }

  /// Takes the lock, or reports who holds it.
  Future<InvoiceEditLockResult> acquire() async {
    if (!ConnectivityService.instance.isOnline) {
      return const InvoiceEditLockResult.allowed();
    }
    try {
      final me = deviceId();
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email') ?? '';
      final result = await _fs.runTransaction((tx) async {
        final snap = await tx.get(_ref);
        final data = snap.data();
        if (data != null && data['deviceId'] != me) {
          final expires = data['expiresAt'];
          final expiresAt = expires is Timestamp ? expires.toDate() : null;
          if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
            return InvoiceEditLockResult.blocked(
                data['userEmail']?.toString() ?? '');
          }
        }
        tx.set(_ref, {
          'invoicePath': invoicePath,
          'deviceId': me,
          'userEmail': email,
          'lockedAt': Timestamp.now(),
          'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
        });
        return const InvoiceEditLockResult.allowed();
      }).timeout(const Duration(seconds: 6));
      if (result.allowed) {
        _held = true;
        _renewTimer?.cancel();
        _renewTimer = Timer.periodic(_renewEvery, (_) => _renew());
      }
      return result;
    } catch (error) {
      // Offline, slow network or missing permission: allow the edit.
      debugPrint('Invoice edit lock unavailable for $invoicePath: $error');
      return const InvoiceEditLockResult.allowed();
    }
  }

  Future<void> _renew() async {
    if (!_held) return;
    try {
      await _ref.set({
        'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
    } catch (error) {
      debugPrint('Invoice edit lock renewal failed for $invoicePath: $error');
    }
  }

  /// Frees the lock when the edit page closes. Safe to call more than once.
  Future<void> release() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    if (!_held) return;
    _held = false;
    try {
      final me = deviceId();
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(_ref);
        if (snap.data()?['deviceId'] == me) tx.delete(_ref);
      }).timeout(const Duration(seconds: 6));
    } catch (error) {
      // The lock expires on its own after [ttl].
      debugPrint('Invoice edit lock release failed for $invoicePath: $error');
    }
  }
}
