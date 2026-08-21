import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kareem_store/repositories/client_repository.dart';
import 'package:kareem_store/repositories/balance_history_repository.dart';
import 'package:kareem_store/repositories/product_repository.dart';
import 'package:kareem_store/local_db/models/balance_history_local.dart';
import 'package:kareem_store/sync/connectivity_service.dart';
import 'package:kareem_store/sync/sync_queue_manager.dart';
import 'package:kareem_store/Services/client_invoice_balance_sync_service.dart';
import 'package:kareem_store/Services/invoice_stock_service.dart';
import 'invoice_state.dart';
import '../product_model.dart';
import 'package:kareem_store/Widgets/egypt_phone_field.dart';

class InvoiceCubit extends Cubit<InvoiceState> {
  InvoiceCubit() : super(const InvoiceState()) {
    _init();
  }

  void _init() {
    emit(state.copyWith(
      selectedDate: DateTime.now(),
    ));
    fetchProducts();
    fetchClients();
  }

  Future<void> fetchClients() async {
    _loadClientsFromLocalCache();
    if (ConnectivityService.instance.isOnline) {
      ClientRepository.instance.deltaSync().then((_) {
        _loadClientsFromLocalCache();
      }).catchError((_) {});
    }
  }

  void _loadClientsFromLocalCache() {
    final locals = ClientRepository.instance.getAll();
    final sorted = locals.map((e) => e.name).toList();
    sorted.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    emit(state.copyWith(clients: sorted));
  }

  Future<void> fetchProducts() async {
    _loadProductsFromLocalCache();
    if (ConnectivityService.instance.isOnline) {
      ProductRepository.instance.deltaSync().then((_) {
        _loadProductsFromLocalCache();
      }).catchError((_) {});
    }
  }

  void _loadProductsFromLocalCache() {
    final locals = ProductRepository.instance.getAll();
    final mapped = locals.map((p) => Product(
      id: p.id,
      randomNumber: 0,
      name: p.name,
      description: p.description,
      sellingPrice1: p.sellingPrice1,
      sellingPrice2: p.sellingPrice2,
      sellingPrice3: p.sellingPrice3,
      costPrice: p.costPrice,
      quantity: p.quantity,
      alertAmount: 0,
      retail: p.retail,
    )).toList();
    emit(state.copyWith(products: mapped, isFetching: false));
  }

  Future<double> fetchClientBalance(String clientName) async {
    return ClientRepository.instance.findByName(clientName)?.balance ?? 0.0;
  }

  void setClientInfo(String clientName, double balance, String paidAmountText) {
    emit(state.copyWith(
      clientName: clientName,
      clientBalance: balance,
      paidAmountText: paidAmountText,
    ));
  }

  Future<void> addNewClient(String name, double balance, String phoneText) async {
    final phone = phoneText.isEmpty ? '' : EgyptPhoneField.toWhatsappDigits(phoneText);
    final docRef = FirebaseFirestore.instance.collection('clients').doc();
    final clientId = docRef.id;
    final data = <String, dynamic>{
      'clientName': name,
      'balance': balance,
      'phone': phone,
      'id': clientId,
    };

    // 1. Save to local Hive database immediately (0ms)
    await ClientRepository.instance.upsertLocal(clientId, data);

    if (balance != 0) {
      await BalanceHistoryRepository.instance.upsertLocal(
        BalanceHistoryLocal(
          id: '${clientId}_opening',
          parentId: clientId,
          parentType: 'client',
          enteredBalance: balance,
          balanceBefore: 0.0,
          type: 'opening',
          timestamp: DateTime.now(),
        ),
      );
    }

    // 2. Sync to Firestore in background / queue for later
    final bool isOnline = ConnectivityService.instance.isOnline;
    if (isOnline) {
      try {
        await docRef.set(data, SetOptions(merge: true));
        if (balance != 0) {
          await docRef
              .collection('balanceHistory')
              .doc('${clientId}_opening')
              .set({
            'enteredBalance': balance,
            'balanceBefore': 0.0,
            'type': 'opening',
            'timestamp': FieldValue.serverTimestamp(),
          });
          await ClientInvoiceBalanceSyncService.syncForClient(clientId);
        }
      } catch (e) {
        await SyncQueueManager.instance.enqueue(
          operationType: 'createClient',
          payload: {'clientId': clientId, 'data': data, 'openingBalance': balance},
        );
      }
    } else {
      await SyncQueueManager.instance.enqueue(
        operationType: 'createClient',
        payload: {'clientId': clientId, 'data': data, 'openingBalance': balance},
      );
    }

    final newClients = List<String>.from(state.clients)..insert(0, name);
    emit(state.copyWith(
      clients: newClients,
      clientName: name,
      clientBalance: balance,
    ));
  }
}
