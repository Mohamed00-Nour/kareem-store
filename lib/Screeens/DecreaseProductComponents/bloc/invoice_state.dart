import '../product_model.dart';

class InvoiceState {
  final List<Product> products;
  final DateTime? selectedDate;
  final List<Map<String, dynamic>> addedProducts;
  final int lineIdCounter;
  final bool dataModified;
  final bool isSaving;
  final bool isFetching;
  final double clientBalance;
  final String clientName;
  final String newClientName;
  final String newClientPhone;
  final double newClientBalance;
  final String productNameQuery;
  final String paidAmountText;
  final List<String> clients;
  final int defaultPriceTier;
  final bool barcodeExternal;
  final bool retailOnlyMode;

  // Editing state
  final Map<String, dynamic>? lastInvoice;
  final String? editingRootInvoiceId;
  final String? editingClientSubDocId;
  final String editingSourceCollection;
  final Map<String, dynamic>? originalInvoice;
  final dynamic editingInvoiceNumber;
  final String editingPaymentMethod;
  final String editingNotes;
  final double editingInvoiceDiscountAmount;

  const InvoiceState({
    this.products = const [],
    this.selectedDate,
    this.addedProducts = const [],
    this.lineIdCounter = 0,
    this.dataModified = false,
    this.isSaving = false,
    this.isFetching = true,
    this.clientBalance = 0.0,
    this.clientName = '',
    this.newClientName = '',
    this.newClientPhone = '',
    this.newClientBalance = 0.0,
    this.productNameQuery = '',
    this.paidAmountText = '',
    this.clients = const [],
    this.defaultPriceTier = 1,
    this.barcodeExternal = false,
    this.retailOnlyMode = false,
    this.lastInvoice,
    this.editingRootInvoiceId,
    this.editingClientSubDocId,
    this.editingSourceCollection = 'invoices',
    this.originalInvoice,
    this.editingInvoiceNumber,
    this.editingPaymentMethod = 'نقداً',
    this.editingNotes = '',
    this.editingInvoiceDiscountAmount = 0.0,
  });

  InvoiceState copyWith({
    List<Product>? products,
    DateTime? selectedDate,
    List<Map<String, dynamic>>? addedProducts,
    int? lineIdCounter,
    bool? dataModified,
    bool? isSaving,
    bool? isFetching,
    double? clientBalance,
    String? clientName,
    String? newClientName,
    String? newClientPhone,
    double? newClientBalance,
    String? productNameQuery,
    String? paidAmountText,
    List<String>? clients,
    int? defaultPriceTier,
    bool? barcodeExternal,
    bool? retailOnlyMode,
    Map<String, dynamic>? lastInvoice,
    String? editingRootInvoiceId,
    String? editingClientSubDocId,
    String? editingSourceCollection,
    Map<String, dynamic>? originalInvoice,
    dynamic editingInvoiceNumber,
    String? editingPaymentMethod,
    String? editingNotes,
    double? editingInvoiceDiscountAmount,
  }) {
    return InvoiceState(
      products: products ?? this.products,
      selectedDate: selectedDate ?? this.selectedDate,
      addedProducts: addedProducts ?? this.addedProducts,
      lineIdCounter: lineIdCounter ?? this.lineIdCounter,
      dataModified: dataModified ?? this.dataModified,
      isSaving: isSaving ?? this.isSaving,
      isFetching: isFetching ?? this.isFetching,
      clientBalance: clientBalance ?? this.clientBalance,
      clientName: clientName ?? this.clientName,
      newClientName: newClientName ?? this.newClientName,
      newClientPhone: newClientPhone ?? this.newClientPhone,
      newClientBalance: newClientBalance ?? this.newClientBalance,
      productNameQuery: productNameQuery ?? this.productNameQuery,
      paidAmountText: paidAmountText ?? this.paidAmountText,
      clients: clients ?? this.clients,
      defaultPriceTier: defaultPriceTier ?? this.defaultPriceTier,
      barcodeExternal: barcodeExternal ?? this.barcodeExternal,
      retailOnlyMode: retailOnlyMode ?? this.retailOnlyMode,
      lastInvoice: lastInvoice ?? this.lastInvoice,
      editingRootInvoiceId: editingRootInvoiceId ?? this.editingRootInvoiceId,
      editingClientSubDocId: editingClientSubDocId ?? this.editingClientSubDocId,
      editingSourceCollection: editingSourceCollection ?? this.editingSourceCollection,
      originalInvoice: originalInvoice ?? this.originalInvoice,
      editingInvoiceNumber: editingInvoiceNumber ?? this.editingInvoiceNumber,
      editingPaymentMethod: editingPaymentMethod ?? this.editingPaymentMethod,
      editingNotes: editingNotes ?? this.editingNotes,
      editingInvoiceDiscountAmount: editingInvoiceDiscountAmount ?? this.editingInvoiceDiscountAmount,
    );
  }
}
