import 'package:cloud_firestore/cloud_firestore.dart';

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
    if (!oldSnap.exists) {
      throw PartyRenameException('العميل غير موجود');
    }

    final oldData = Map<String, dynamic>.from(oldSnap.data()!);
    final oldName = (oldData['clientName'] ?? oldClientId).toString().trim();

    if (trimmed == oldClientId && trimmed == oldName) return;

    if (trimmed != oldClientId) {
      final existing = await _firestore.collection('clients').doc(trimmed).get();
      if (existing.exists) {
        throw PartyRenameException('يوجد عميل بهذا الاسم بالفعل');
      }
    }

    final namesToUpdate = <String>{oldName, oldClientId}
      ..removeWhere((n) => n.isEmpty);

    if (trimmed != oldClientId) {
      await _migrateClientDocument(
        oldClientId: oldClientId,
        newClientId: trimmed,
        oldData: oldData,
      );
    } else {
      await oldRef.update({'clientName': trimmed});
    }

    await _updateClientNameInCollection('invoices', namesToUpdate, trimmed);
    await _updateClientNameInCollection('returnInvoices', namesToUpdate, trimmed);
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
    for (final doc in dup.docs) {
      if (doc.id != supplierId) {
        throw PartyRenameException('يوجد مورد بهذا الاسم بالفعل');
      }
    }

    await supplierRef.update({'name': trimmed});

    if (oldName.isNotEmpty) {
      await _updateSupplierNameInBuyingInvoices(oldName, trimmed);
    }
  }

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
      batch.update(ref, {'clientName': newName});
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
      batch.update(doc.reference, {'supplierName': newName});
      opCount++;
      if (opCount >= _maxBatchOps) {
        await commitBatch();
      }
    }
    await commitBatch();
  }
}
