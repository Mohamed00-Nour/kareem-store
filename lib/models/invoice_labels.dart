class InvoiceLabels {
  final String invoiceTitle;
  final String invoiceNumber;
  final String date;
  final String client;
  final String total;
  final String paid;
  final String balance;
  final String previousBalance;
  final String product;
  final String quantity;
  final String price;
  final String lineTotal;
  final String address;
  final String phone;
  final String description;
  final String productNumber;
  final String expiryDate;

  const InvoiceLabels({
    this.invoiceTitle = 'فاتورة مبيعات',
    this.invoiceNumber = 'رقم الفاتورة',
    this.date = 'التاريخ',
    this.client = 'العميل',
    this.total = 'الإجمالي',
    this.paid = 'المدفوع',
    this.balance = 'المتبقي',
    this.previousBalance = 'الرصيد السابق',
    this.product = 'اسم المنتج',
    this.quantity = 'الكمية',
    this.price = 'السعر',
    this.lineTotal = 'الإجمالي',
    this.address = 'العنوان',
    this.phone = 'التليفون',
    this.description = 'الوصف',
    this.productNumber = 'رقم المنتج',
    this.expiryDate = 'تاريخ الانتهاء',
  });

  InvoiceLabels copyWith({
    String? invoiceTitle,
    String? invoiceNumber,
    String? date,
    String? client,
    String? total,
    String? paid,
    String? balance,
    String? previousBalance,
    String? product,
    String? quantity,
    String? price,
    String? lineTotal,
    String? address,
    String? phone,
    String? description,
    String? productNumber,
    String? expiryDate,
  }) {
    return InvoiceLabels(
      invoiceTitle: invoiceTitle ?? this.invoiceTitle,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      date: date ?? this.date,
      client: client ?? this.client,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      balance: balance ?? this.balance,
      previousBalance: previousBalance ?? this.previousBalance,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      lineTotal: lineTotal ?? this.lineTotal,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      description: description ?? this.description,
      productNumber: productNumber ?? this.productNumber,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  Map<String, dynamic> toMap() => {
        'invoiceTitle': invoiceTitle,
        'invoiceNumber': invoiceNumber,
        'date': date,
        'client': client,
        'total': total,
        'paid': paid,
        'balance': balance,
        'previousBalance': previousBalance,
        'product': product,
        'quantity': quantity,
        'price': price,
        'lineTotal': lineTotal,
        'address': address,
        'phone': phone,
        'description': description,
        'productNumber': productNumber,
        'expiryDate': expiryDate,
      };

  factory InvoiceLabels.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const InvoiceLabels();
    return InvoiceLabels(
      invoiceTitle: map['invoiceTitle'] as String? ?? 'فاتورة مبيعات',
      invoiceNumber: map['invoiceNumber'] as String? ?? 'رقم الفاتورة',
      date: map['date'] as String? ?? 'التاريخ',
      client: map['client'] as String? ?? 'العميل',
      total: map['total'] as String? ?? 'الإجمالي',
      paid: map['paid'] as String? ?? 'المدفوع',
      balance: map['balance'] as String? ?? 'المتبقي',
      previousBalance: map['previousBalance'] as String? ?? 'الرصيد السابق',
      product: map['product'] as String? ?? 'اسم المنتج',
      quantity: map['quantity'] as String? ?? 'الكمية',
      price: map['price'] as String? ?? 'السعر',
      lineTotal: map['lineTotal'] as String? ?? 'الإجمالي',
      address: map['address'] as String? ?? 'العنوان',
      phone: map['phone'] as String? ?? 'التليفون',
      description: map['description'] as String? ?? 'الوصف',
      productNumber: map['productNumber'] as String? ?? 'رقم المنتج',
      expiryDate: map['expiryDate'] as String? ?? 'تاريخ الانتهاء',
    );
  }
}
