import 'package:flutter/material.dart';

import 'DecreaseProductPage.dart';

/// Return invoices — same UI as sales with reversed stock/profit/box logic.
class ReturnProductPage extends StatelessWidget {
  const ReturnProductPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecreaseProductPage(isReturnInvoice: true);
  }
}
