import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../repositories/product_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';

/// Real-time stream listener that bridges Firestore database changes directly
/// into local Hive boxes. Enables immediate cross-device live streaming of
/// products stock, sales invoices, buying invoices, and client/supplier balances.
class RealtimeSyncService {
  RealtimeSyncService._();
  static final RealtimeSyncService instance = RealtimeSyncService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  final List<StreamSubscription> _subscriptions = [];
  bool _isListening = false;

  bool get isListening => _isListening;

  /// Starts global real-time stream listeners for key Firestore collections.
  void startListening() {
    if (_isListening) return;
    _isListening = true;

    _listenToProducts();
    _listenToSalesInvoices();
    _listenToBuyingInvoices();
    _listenToReturnInvoices();
    _listenToClients();
    _listenToSuppliers();
  }

  /// Cancels all active real-time listeners.
  Future<void> stopListening() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _isListening = false;
  }

  // ── 1. Products Stream ───────────────────────────────────────────────────
  void _listenToProducts() {
    final sub = _fs.collection('products').snapshots().listen(
      (snapshot) {
        final Map<String, Map<String, dynamic>> toUpsert = {};
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            ProductRepository.instance.deleteLocal(docId);
          } else if (data != null) {
            toUpsert[docId] = data;
          }
        }
        if (toUpsert.isNotEmpty) {
          ProductRepository.instance.upsertAllLocal(toUpsert);
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService products error: $e');
      },
    );
    _subscriptions.add(sub);
  }

  // ── 2. Sales Invoices Stream ──────────────────────────────────────────────
  void _listenToSalesInvoices() {
    final sub = _fs.collection('invoices').snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            InvoiceRepository.instance.deleteSaleLocal(docId);
          } else if (data != null) {
            InvoiceRepository.instance.upsertSaleLocal(docId, data);
          }
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService sales invoices error: $e');
      },
    );
    _subscriptions.add(sub);
  }

  // ── 3. Buying Invoices Stream ─────────────────────────────────────────────
  void _listenToBuyingInvoices() {
    final sub = _fs.collection('buying invoices').snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            InvoiceRepository.instance.deleteBuyingLocal(docId);
          } else if (data != null) {
            InvoiceRepository.instance.upsertBuyingLocal(docId, data);
          }
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService buying invoices error: $e');
      },
    );
    _subscriptions.add(sub);
  }

  // ── 4. Return Invoices Stream ─────────────────────────────────────────────
  void _listenToReturnInvoices() {
    final sub = _fs.collection('returnInvoices').snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            InvoiceRepository.instance.deleteReturnLocal(docId);
          } else if (data != null) {
            InvoiceRepository.instance.upsertReturnLocal(docId, data);
          }
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService return invoices error: $e');
      },
    );
    _subscriptions.add(sub);
  }

  // ── 5. Clients Stream ─────────────────────────────────────────────────────
  void _listenToClients() {
    final sub = _fs.collection('clients').snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            ClientRepository.instance.deleteLocal(docId);
          } else if (data != null) {
            ClientRepository.instance.upsertLocal(docId, data);
          }
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService clients error: $e');
      },
    );
    _subscriptions.add(sub);
  }

  // ── 6. Suppliers Stream ───────────────────────────────────────────────────
  void _listenToSuppliers() {
    final sub = _fs.collection('suppliers').snapshots().listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          final data = change.doc.data();
          if (change.type == DocumentChangeType.removed) {
            SupplierRepository.instance.deleteLocal(docId);
          } else if (data != null) {
            SupplierRepository.instance.upsertLocal(docId, data);
          }
        }
      },
      onError: (e) {
        debugPrint('RealtimeSyncService suppliers error: $e');
      },
    );
    _subscriptions.add(sub);
  }
}
