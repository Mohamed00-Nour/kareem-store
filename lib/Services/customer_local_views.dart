import '../local_db/hive_init.dart';
import '../repositories/client_repository.dart';
import 'customer_balance_store.dart';

class LocalCustomerDocument {
  final String id;
  final Map<String, dynamic> _data;
  const LocalCustomerDocument(this.id, this._data);
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);
  dynamic operator [](String key) => _data[key];
}

class LocalCustomerSnapshot {
  final List<LocalCustomerDocument> docs;
  const LocalCustomerSnapshot(this.docs);
}

/// All customer balance lists and exports use the same accepted local ledger.
class CustomerLocalViews {
  static LocalCustomerSnapshot snapshot({int balanceSign = 0}) {
    final clients = ClientRepository.instance.getAll();
    final balances = CustomerBalanceStore.balancesForClients(clients);
    return LocalCustomerSnapshot(clients
        .map((client) => LocalCustomerDocument(client.id, {
              'id': client.id,
              'clientName': client.name,
              'name': client.name,
              'balance': balances[client.id],
              'phone': client.phone,
              'address': client.address,
            }))
        .where((doc) =>
            balanceSign == 0 ||
            (balanceSign > 0 ? doc['balance'] > 0 : doc['balance'] < 0))
        .toList());
  }

  static Stream<LocalCustomerSnapshot> watch({int balanceSign = 0}) async* {
    yield snapshot(balanceSign: balanceSign);
    yield* clientsBox.watch().map((_) => snapshot(balanceSign: balanceSign));
  }

  static List<Map<String, dynamic>> vouchers() => appMetaBox.keys
      .where((key) => key.toString().startsWith('customerVoucher:'))
      .map((key) => Map<String, dynamic>.from(appMetaBox.get(key) as Map))
      .toList();

  static int reserveVoucherNumber() {
    var latest =
        (appMetaBox.get('nextCustomerVoucherNumber', defaultValue: 0) as num)
            .toInt();
    for (final voucher in vouchers()) {
      final number =
          int.tryParse(voucher['voucherNumber']?.toString() ?? '') ?? 0;
      if (number > latest) latest = number;
    }
    appMetaBox.put('nextCustomerVoucherNumber', latest + 1);
    return latest + 1;
  }
}
