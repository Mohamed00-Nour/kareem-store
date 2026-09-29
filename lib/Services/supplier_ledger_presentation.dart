class SupplierLedgerPresentation {
  SupplierLedgerPresentation._();

  static bool voucherIncreasesBalance(String? direction) {
    return direction?.trim() == 'له';
  }

  static String voucherSign(String? direction) {
    return voucherIncreasesBalance(direction) ? '+' : '-';
  }

  static String voucherLabel(
    String? direction, {
    String voucherNumber = '',
  }) {
    final label = voucherIncreasesBalance(direction)
        ? 'إضافة رصيد للمورد'
        : 'سداد نقدي للمورد';
    final number = voucherNumber.trim();
    return number.isEmpty ? label : '$label (إيصال #$number)';
  }
}
