import '../repositories/balance_history_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/invoice_repository.dart';
import 'sales_invoice_actions_service.dart';

class CustomerStatementData {
  static bool increases(String type) =>
      ['opening', 'sale', 'addition', 'return_payment'].contains(type);

  static List<Map<String, dynamic>> financialHistory(String clientId) {
    final history = BalanceHistoryRepository.instance.getForClient(clientId);
    final net = history.fold<double>(
        0,
        (sum, entry) =>
            sum + (increases(entry.type) ? 1 : -1) * entry.enteredBalance);
    var running =
        ClientRepository.instance.computeLiveBalanceFromHive(clientId) - net;
    return history.map((entry) {
      final before = running;
      running += (increases(entry.type) ? 1 : -1) * entry.enteredBalance;
      return {
        ...entry.toMap(),
        'balanceBefore': before,
        'balanceAfter': running
      };
    }).toList();
  }

  static List<Map<String, dynamic>> invoices(String clientId,
      {bool returns = false}) {
    final name = ClientRepository.instance.getById(clientId)?.name;
    final invoices = returns
        ? InvoiceRepository.instance
            .getReturnsByClient(clientId, clientName: name)
        : InvoiceRepository.instance
            .getSalesByClient(clientId, clientName: name);
    return invoices
        .map((invoice) =>
            SalesInvoiceActionsService.buildClientPagePayload(invoice.toMap()))
        .toList();
  }
}
