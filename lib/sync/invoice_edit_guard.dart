import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../local_db/hive_init.dart';
import '../repositories/invoice_repository.dart';
import 'cloud_snapshot_guard.dart';
import 'connectivity_service.dart';
import 'financial_cloud_store.dart';
import 'invoice_edit_lock.dart';

/// What the save-time check found in the cloud.
enum CloudInvoiceChange { none, changed, deleted }

/// Stops an invoice edit from being saved over a newer version that another
/// device already uploaded, and shows the "being edited" block.
class InvoiceEditGuard {
  InvoiceEditGuard._();

  static Map<String, dynamic>? _localInvoice(String path) {
    final parts = path.split('/');
    if (parts.length != 2) return null;
    switch (parts[0]) {
      case 'invoices':
        return InvoiceRepository.instance.getSaleById(parts[1])?.toMap();
      case 'returnInvoices':
        return InvoiceRepository.instance.getReturnById(parts[1])?.toMap();
      case 'buying invoices':
        return buyingInvoicesBox.get(parts[1])?.toMap();
    }
    return null;
  }

  static Future<void> _storeLocally(
      String path, Map<String, dynamic>? data) async {
    final parts = path.split('/');
    if (parts[0] == 'buying invoices') {
      await InvoiceRepository.instance.mergeCloudBuying(parts[1], data);
    } else {
      await InvoiceRepository.instance
          .mergeCloudInvoice(parts[0], parts[1], data);
    }
  }

  /// Compares the invoice this device has with the cloud copy. Offline, slow
  /// network, or a change of this device still waiting to upload all count as
  /// [CloudInvoiceChange.none]: the sync-time conflict check covers them.
  /// A newer cloud version is stored locally so reopening shows it.
  static Future<CloudInvoiceChange> findCloudChange(String path) async {
    if (!ConnectivityService.instance.isOnline) return CloudInvoiceChange.none;
    if (CloudSnapshotGuard.pendingPath(path)) return CloudInvoiceChange.none;
    final local = _localInvoice(path);
    if (local == null) return CloudInvoiceChange.none;

    Map<String, dynamic>? cloud;
    try {
      final snap = await FirebaseFirestore.instance
          .doc(path)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      if (!snap.exists) return CloudInvoiceChange.none;
      cloud = snap.data();
    } catch (_) {
      return CloudInvoiceChange.none;
    }
    if (cloud == null) return CloudInvoiceChange.none;

    if (cloud['_deleted'] == true) {
      await _storeLocally(path, cloud);
      return CloudInvoiceChange.deleted;
    }
    final contentChanged = financialStateDifference(
            financialInvoiceState(cloud), financialInvoiceState(local)) !=
        null;
    final cloudStamp = cloud['_operationId'];
    final knownStamp = appMetaBox
        .get(CloudSnapshotGuard.operationKey(path), defaultValue: '')
        .toString();
    final otherDeviceStamp = cloudStamp is String &&
        cloudStamp.isNotEmpty &&
        knownStamp.isNotEmpty &&
        cloudStamp != knownStamp &&
        !CloudSnapshotGuard.knowsOperation(cloudStamp);
    if (!contentChanged && !otherDeviceStamp) return CloudInvoiceChange.none;

    await _storeLocally(path, cloud);
    return CloudInvoiceChange.changed;
  }

  /// Returns true when the edit may be saved. Otherwise explains why it was
  /// not saved; the caller should close the edit page.
  static Future<bool> confirmLatestBeforeSave(
      BuildContext context, String path) async {
    final change = await findCloudChange(path);
    if (change == CloudInvoiceChange.none) return true;
    if (!context.mounted) return false;
    await _showMessage(
      context,
      title: 'لم يتم حفظ التعديل',
      message: change == CloudInvoiceChange.deleted
          ? 'تم حذف هذه الفاتورة من مستخدم آخر بعد أن فتحتها، لذلك لم يتم حفظ تعديلك.'
          : 'تم تعديل هذه الفاتورة من مستخدم آخر بعد أن فتحتها، لذلك لم يتم حفظ تعديلك.\n'
              'افتح الفاتورة مرة أخرى لرؤية آخر نسخة ثم أعد التعديل.',
    );
    return false;
  }

  /// Takes the edit lock. Returns the held lock, or null after telling the
  /// user that another device is editing this invoice (the caller should
  /// close the edit page).
  static Future<InvoiceEditLock?> lockForEditing(
      BuildContext context, String path) async {
    final lock = InvoiceEditLock(path);
    final result = await lock.acquire();
    if (result.allowed) {
      if (context.mounted) return lock;
      await lock.release();
      return null;
    }
    if (context.mounted) {
      final who = (result.lockedBy ?? '').trim();
      await _showMessage(
        context,
        title: 'الفاتورة قيد التعديل',
        message: 'هذه الفاتورة مفتوحة للتعديل الآن على جهاز آخر'
            '${who.isEmpty ? '' : ' بواسطة $who'}.\n'
            'لا يمكن تعديلها حتى ينتهي من التعديل ويغلق الفاتورة.',
      );
    }
    return null;
  }

  static Future<void> _showMessage(BuildContext context,
      {required String title, required String message}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }
}
