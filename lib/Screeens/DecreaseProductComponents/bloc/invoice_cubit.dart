import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kareem_store/repositories/client_repository.dart';
import 'package:kareem_store/repositories/product_repository.dart';
import 'package:kareem_store/local_db/hive_init.dart';
import 'package:kareem_store/sync/connectivity_service.dart';
import 'package:kareem_store/Services/quick_entity_creation_service.dart';
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
    clientsBox.listenable().addListener(_loadClientsFromLocalCache);
    productsBox.listenable().addListener(_loadProductsFromLocalCache);
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
    final mapped = locals
        .map((p) => Product(
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
            ))
        .toList();
    emit(state.copyWith(products: mapped, isFetching: false));
  }

  Future<double> fetchClientBalance(String clientName) async {
    return ClientRepository.instance.currentBalanceByName(clientName);
  }

  void setClientInfo(String clientName, double balance, String paidAmountText) {
    emit(state.copyWith(
      clientName: clientName,
      clientBalance: balance,
      paidAmountText: paidAmountText,
    ));
  }

  Future<void> addNewClient(
      String name, double balance, String phoneText) async {
    final phone =
        phoneText.isEmpty ? '' : EgyptPhoneField.toWhatsappDigits(phoneText);
    final client = await QuickEntityCreationService.instance.createClient(
      name: name,
      openingBalance: balance,
      phone: phone,
    );
    unawaited(ConnectivityService.instance.forceSync());

    final newClients = List<String>.from(state.clients);
    if (!newClients.contains(client.name)) newClients.insert(0, client.name);
    emit(state.copyWith(
      clients: newClients,
      clientName: client.name,
      clientBalance: balance,
    ));
  }

  @override
  Future<void> close() {
    clientsBox.listenable().removeListener(_loadClientsFromLocalCache);
    productsBox.listenable().removeListener(_loadProductsFromLocalCache);
    return super.close();
  }
}
