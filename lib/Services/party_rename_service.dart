import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../local_db/hive_init.dart';
import '../local_db/models/invoice_local.dart';
import '../sync/firestore_read_diagnostics.dart';
import '../sync/local_operation_journal.dart';

class PartyRenameException implements Exception {
  final String message;
  PartyRenameException(this.message);

  @override
  String toString() => message;
}

class PartyRenameService {
  static const _maxBatchOps = 450;

  static final _firestore = FirebaseFirestore.instance;

  static Future<void> renameClient({
    required String oldClientId,
    required String newName,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw PartyRenameException('الاسم فارغ');
    }

    final oldRef = _firestore.collection('clients').doc(oldClientId);
    final oldSnap = await oldRef.get();
    FirestoreReadDiagnostics.queryResult(
      'clients/$oldClientId',
      oldSnap.exists ? 1 : 0,
      trigger: 'rename client',
      fromCache: oldSnap.metadata.isFromCache,
    );
    if (!oldSnap.exists) {
      throw PartyRenameException('العميل غير موجود');
    }

    final oldData = Map<String, dynamic>.from(oldSnap.data()!);
    final oldName = (oldData['clientName'] ?? '').toString().trim();

    if (trimmed == oldName) return;

    // Check for duplicate names
    final dup = await _firestore
        .collection('clients')
        .where('clientName', isEqualTo: trimmed)
        .limit(2)
        .get();
    FirestoreReadDiagnostics.queryResult(
      'clients where clientName == new name limit 2',
      dup.docs.length,
      trigger: 'rename client duplicate check',
      fromCache: dup.metadata.isFromCache,
    );
    for (final doc in dup.docs) {
      if (doc.id != oldClientId) {
        throw PartyRenameException('يوجد عميل بهذا الاسم بالفعل');
      }
    }

    await oldRef.update({
      'clientName': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final namesToUpdate = <String>{oldName}..removeWhere((n) => n.isEmpty);
    if (namesToUpdate.isNotEmpty) {
      await _updateClientNameInCollection('invoices', namesToUpdate, trimmed);
      await _updateClientNameInCollection(
          'returnInvoices', namesToUpdate, trimmed);
    }
    await _renameLocally(
      partyBox: clientsBox,
      partyId: oldClientId,
      invoiceBoxes: [invoicesBox, returnInvoicesBox],
      oldNames: namesToUpdate,
      newName: trimmed,
      isSupplier: false,
    );
  }

  static Future<void> renameSupplier({
    required String supplierId,
    required String newName,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw PartyRenameException('الاسم فارغ');
    }

    final supplierRef = _firestore.collection('suppliers').doc(supplierId);
    final snap = await supplierRef.get();
    FirestoreReadDiagnostics.queryResult(
      'suppliers/$supplierId',
      snap.exists ? 1 : 0,
      trigger: 'rename supplier',
      fromCache: snap.metadata.isFromCache,
    );
    if (!snap.exists) {
      throw PartyRenameException('المورد غير موجود');
    }

    final oldName = (snap.data()?['name'] ?? '').toString().trim();
    if (trimmed == oldName) return;

    final dup = await _firestore
        .collection('suppliers')
        .where('name', isEqualTo: trimmed)
        .limit(2)
        .get();
    FirestoreReadDiagnostics.queryResult(
      'suppliers where name == new name limit 2',
      dup.docs.length,
      trigger: 'rename supplier duplicate check',
      fromCache: dup.metadata.isFromCache,
    );
    for (final doc in dup.docs) {
      if (doc.id != supplierId) {
        throw PartyRenameException('يوجد مورد بهذا الاسم بالفعل');
      }
    }

    await supplierRef.update({
      'name': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (oldName.isNotEmpty) {
      await _updateSupplierNameInBuyingInvoices(oldName, trimmed);
    }
    await _renameLocally(
      partyBox: suppliersBox,
      partyId: supplierId,
      invoiceBoxes: [buyingInvoicesBox],
      oldNames: {oldName}..removeWhere((n) => n.isEmpty),
      newName: trimmed,
      isSupplier: true,
    );
  }

  /// Applies a completed Firestore rename to the matching local records, so
  /// the next invoice edit starts from the same name that is in the cloud.
  static Future<void> _renameLocally({
    required Box partyBox,
    required String partyId,
    required List<Box<InvoiceLocal>> invoiceBoxes,
    required Set<String> oldNames,
    required String newName,
    required bool isSupplier,
  }) =>
      LocalOperationJournal.exclusive(() async {
        final party = partyBox.get(partyId);
        if (party != null && party.name != newName) {
          party.name = newName;
          await partyBox.put(partyId, party);
          await partyBox.flush();
        }
        if (oldNames.isEmpty) return;
        for (final box in invoiceBoxes) {
          final changed = <dynamic, InvoiceLocal>{};
          for (final key in box.keys) {
            final invoice = box.get(key);
            if (invoice == null) continue;
            final name = isSupplier ? invoice.supplierName : invoice.clientName;
            if (!oldNames.contains(name)) continue;
            if (isSupplier) {
              invoice.supplierName = newName;
            } else {
              invoice.clientName = newName;
            }
            changed[key] = invoice;
          }
          if (changed.isNotEmpty) {
            await box.putAll(changed);
            await box.flush();
          }
        }
      });

  static Future<void> _migrateClientDocument({
    required String oldClientId,
    required String newClientId,
    required Map<String, dynamic> oldData,
  }) async {
    final oldRef = _firestore.collection('clients').doc(oldClientId);
    final newRef = _firestore.collection('clients').doc(newClientId);

    await _migrateSubcollection(oldRef, newRef, 'invoices');
    await _migrateSubcollection(oldRef, newRef, 'balanceHistory');

    final newData = Map<String, dynamic>.from(oldData);
    newData['clientName'] = newClientId;
    newData['id'] = newClientId;

    await newRef.set(newData);
    await oldRef.delete();
  }

  static Future<void> _migrateSubcollection(
    DocumentReference oldParent,
    DocumentReference newParent,
    String subcollectionName,
  ) async {
    final snap = await oldParent.collection(subcollectionName).get();
    if (snap.docs.isEmpty) return;

    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      opCount = 0;
    }

    for (final doc in snap.docs) {
      final newDocRef = newParent.collection(subcollectionName).doc(doc.id);
      batch.set(newDocRef, doc.data());
      batch.delete(doc.reference);
      opCount += 2;
      if (opCount >= _maxBatchOps) {
        await commitBatch();
      }
    }
    await commitBatch();
  }

  static Future<void> _updateClientNameInCollection(
    String collection,
    Set<String> oldNames,
    String newName,
  ) async {
    final docRefs = <DocumentReference>{};

    for (final oldName in oldNames) {
      final snap = await _firestore
          .collection(collection)
          .where('clientName', isEqualTo: oldName)
          .get();
      FirestoreReadDiagnostics.queryResult(
        '$collection where clientName == old name',
        snap.docs.length,
        trigger: 'rename client references',
        fromCache: snap.metadata.isFromCache,
      );
      for (final doc in snap.docs) {
        docRefs.add(doc.reference);
      }
    }

    if (docRefs.isEmpty) return;

    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      opCount = 0;
    }

    for (final ref in docRefs) {
      batch.update(ref, {
        'clientName': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      opCount++;
      if (opCount >= _maxBatchOps) {
        await commitBatch();
      }
    }
    await commitBatch();
  }

  static Future<void> _updateSupplierNameInBuyingInvoices(
    String oldName,
    String newName,
  ) async {
    final snap = await _firestore
        .collection('buying invoices')
        .where('supplierName', isEqualTo: oldName)
        .get();
    FirestoreReadDiagnostics.queryResult(
      'buying invoices where supplierName == old name',
      snap.docs.length,
      trigger: 'rename supplier references',
      fromCache: snap.metadata.isFromCache,
    );

    if (snap.docs.isEmpty) return;

    WriteBatch batch = _firestore.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      opCount = 0;
    }

    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'supplierName': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      opCount++;
      if (opCount >= _maxBatchOps) {
        await commitBatch();
      }
    }
    await commitBatch();
  }
}
