part of client_invoices_page;

class _InvoiceEditSheet extends StatefulWidget {
  final DocumentSnapshot invoice;
  final Map<String, dynamic> invoiceData;
  final List<Map<String, dynamic>> originalProducts;
  final List<_ProdInfo> allProds;
  final String clientId;
  final Future<void> Function(
    String clientInvoiceDocId,
    Map<String, dynamic> fields,
  ) onSyncRoot;

  const _InvoiceEditSheet({
    required this.invoice,
    required this.invoiceData,
    required this.originalProducts,
    required this.allProds,
    required this.clientId,
    required this.onSyncRoot,
  });

  @override
  State<_InvoiceEditSheet> createState() => _InvoiceEditSheetState();
}

class _InvoiceEditSheetState extends State<_InvoiceEditSheet> {
  late final List<_EditRow> rows;
  late final TextEditingController paidCtrl;
  late final ValueNotifier<bool> isSaving;
  bool _qtyAutoSelected = false;

  static double _num(dynamic value) {
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is num) return value.toDouble();
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    rows = widget.originalProducts.map((p) {
      final storedPrice = double.tryParse(p['selectedPrice'].toString()) ?? 0.0;
      _ProdInfo? info = widget.allProds.cast<_ProdInfo?>().firstWhere(
            (pi) => pi!.name == p['product'].toString(),
            orElse: () => null,
          );
      info ??= _ProdInfo(
        name: p['product'].toString(),
        sellingPrice1: storedPrice,
        sellingPrice2: storedPrice,
        sellingPrice3: storedPrice,
        quantity: 0.0,
      );
      int tier = 1;
      if (storedPrice == info.sellingPrice2) {
        tier = 2;
      } else if (storedPrice == info.sellingPrice3) {
        tier = 3;
      } else if (storedPrice != info.sellingPrice1) {
        tier = 0;
      }
      return _EditRow(
        prodInfo: info,
        amount: double.tryParse(p['amount'].toString()) ?? 1.0,
        priceTier: tier,
        customPrice: storedPrice,
      );
    }).toList();

    paidCtrl = TextEditingController(
      text: _num(widget.invoiceData['paidAmount']).toStringAsFixed(2),
    );
    isSaving = ValueNotifier(false);
  }

  @override
  void dispose() {
    isSaving.dispose();
    paidCtrl.dispose();
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _setSheet(VoidCallback fn) => setState(fn);

  Future<void> _save() async {
    isSaving.value = true;
    try {
      final updatedProducts = rows
          .where((r) => r.prodInfo != null && r.prodInfo!.name.isNotEmpty)
          .map((r) => {
                'product': r.prodInfo!.name,
                'amount': r.amount,
                'selectedPrice': r.price,
                'total': r.total,
              })
          .toList();

      for (var op in widget.originalProducts) {
        final oa = double.tryParse(op['amount'].toString()) ?? 0.0;
        if (oa <= 0) continue;
        final q = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: op['product'])
            .get();
        for (var doc in q.docs) {
          final qty = (doc['quantity'] as num).toDouble();
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .update({'quantity': qty + oa});
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': DateTime.now(),
            'amount': oa,
            'type': 'increase',
          });
        }
      }

      for (var np in updatedProducts) {
        final na = double.tryParse(np['amount'].toString()) ?? 0.0;
        if (na <= 0) continue;
        final q = await FirebaseFirestore.instance
            .collection('products')
            .where('name', isEqualTo: np['product'])
            .get();
        for (var doc in q.docs) {
          final qty = (doc['quantity'] as num).toDouble();
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .update({'quantity': qty - na});
          await FirebaseFirestore.instance
              .collection('products')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': DateTime.now(),
            'amount': na,
            'type': 'decrease',
          });
        }
      }

      final newTotalSum = updatedProducts.fold(
        0.0,
        (s, p) => s + (double.tryParse(p['total'].toString()) ?? 0.0),
      );
      var newPaid =
          double.tryParse(paidCtrl.text.replaceAll(',', '.')) ?? 0.0;
      if (newPaid < 0) newPaid = 0;
      if (newPaid > newTotalSum) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('المدفوع لا يمكن أن يكون أكبر من إجمالي الفاتورة'),
          ));
        }
        isSaving.value = false;
        return;
      }

      final newInvoiceBalance = newTotalSum - newPaid;

      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('invoices')
          .doc(widget.invoice.id)
          .update({
        'products': updatedProducts,
        'totalSum': newTotalSum,
        'paidAmount': newPaid,
        'balance': newInvoiceBalance,
      });
      await widget.onSyncRoot(widget.invoice.id, {
        'products': updatedProducts,
        'totalSum': newTotalSum,
        'paidAmount': newPaid,
        'balance': newInvoiceBalance,
      });

      await ClientInvoiceBalanceSyncService.syncForClient(widget.clientId);

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
      isSaving.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_qtyAutoSelected && rows.isNotEmpty) {
      _qtyAutoSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectAllField(rows.first.qtyCtrl);
      });
    }

    final invoiceTotal = rows.fold(0.0, (s, r) => s + r.total);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, scrollCtrl) {
          return Column(children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text(
                  'الإجمالي: ${invoiceTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
                const Spacer(),
                Text(
                  'فاتورة #${widget.invoiceData['invoiceNumber']}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]),
            ),
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'المدفوع',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: paidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onTap: () => _selectAllField(paidCtrl),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'المتبقي عليكم',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: paidCtrl,
                          builder: (_, value, __) {
                            final paid = double.tryParse(
                                    value.text.replaceAll(',', '.')) ??
                                0.0;
                            final currentTotal = invoiceNum(
                                widget.invoiceData['balance']);
                            final oldUnpaid = invoiceUnpaidAmount(
                                widget.invoiceData);
                            final newUnpaid = invoiceTotal - paid;
                            final remaining =
                                currentTotal - oldUnpaid + newUnpaid;
                            return Text(
                              remaining.toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: remaining > 0
                                    ? Colors.redAccent
                                    : Colors.green.shade700,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                itemCount: rows.length + 1,
                itemBuilder: (_, i) {
                  if (i == rows.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _setSheet(() => rows.add(_EditRow(
                              prodInfo: null,
                              amount: 1.0,
                              priceTier: 1,
                              customPrice: 0.0,
                            ))),
                        icon: const Icon(Icons.add, color: Colors.orange),
                        label: const Text('إضافة منتج',
                            style: TextStyle(color: Colors.orange)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    );
                  }
                  return _buildEditRowCard(
                    rows[i],
                    i,
                    rows,
                    _setSheet,
                    widget.allProds,
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 8,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: isSaving,
                builder: (_, saving, __) => Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(context),
                      child: const Text('تراجع',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.withOpacity(0.85),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: saving ? null : _save,
                      child: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('حفظ التعديلات',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              )),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

Widget _buildEditRowCard(
  _EditRow row,
  int index,
  List<_EditRow> rows,
  void Function(VoidCallback fn) setSheet,
  List<_ProdInfo> allProds,
) {
  return Card(
    key: ValueKey(row.key),
    margin: const EdgeInsets.symmetric(vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: RawAutocomplete<_ProdInfo>(
                textEditingController: row.nameCtrl,
                focusNode: row.nameFocus,
                optionsBuilder: (val) {
                  if (val.text.isEmpty) {
                    return const Iterable<_ProdInfo>.empty();
                  }
                  return allProds.where((p) => p.name
                      .toLowerCase()
                      .contains(val.text.toLowerCase()));
                },
                displayStringForOption: (p) => p.name,
                optionsViewBuilder: (ctx, onSel, opts) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: opts.length,
                          itemBuilder: (_, j) {
                            final p = opts.elementAt(j);
                            return ListTile(
                              dense: true,
                              title:
                                  Text(p.name, textAlign: TextAlign.right),
                              subtitle: Text(
                                'س1: ${p.sellingPrice1.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              onTap: () => onSel(p),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                fieldViewBuilder: (ctx, ctrl, focus, _) {
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Colors.orange),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.orange, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 10,
                      ),
                    ),
                    onTap: () => _selectAllField(ctrl),
                  );
                },
                onSelected: (p) {
                  setSheet(() {
                    row.prodInfo = p;
                    row.customPrice =
                        p.priceForTier(row.priceTier, row.customPrice);
                    row.customPriceCtrl.text =
                        row.customPrice.toStringAsFixed(2);
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => setSheet(() => rows.removeAt(index)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  row.price.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _PriceTierBtn(
              label: '3',
              selected: row.priceTier == 3,
              onTap: () => setSheet(() => row.priceTier = 3),
            ),
            const SizedBox(width: 3),
            _PriceTierBtn(
              label: '2',
              selected: row.priceTier == 2,
              onTap: () => setSheet(() => row.priceTier = 2),
            ),
            const SizedBox(width: 3),
            _PriceTierBtn(
              label: '1',
              selected: row.priceTier == 1,
              onTap: () => setSheet(() => row.priceTier = 1),
            ),
            const SizedBox(width: 3),
            _PriceTierBtn(
              label: 'خ',
              selected: row.priceTier == 0,
              onTap: () => setSheet(() => row.priceTier = 0),
            ),
            const SizedBox(width: 6),
            const Text('السعر', style: TextStyle(fontSize: 12)),
          ]),
          if (row.priceTier == 0) ...[
            const SizedBox(height: 6),
            TextField(
              controller: row.customPriceCtrl,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'سعر خاص',
                isDense: true,
                prefixIcon:
                    const Icon(Icons.edit, color: Colors.orange, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Colors.orange, width: 2),
                ),
              ),
              onTap: () => _selectAllField(row.customPriceCtrl),
              onChanged: (v) =>
                  setSheet(() => row.customPrice = double.tryParse(v) ?? 0.0),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  row.total.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _CircleBtn(
              icon: Icons.remove,
              onTap: () {
                if (row.amount > 1) {
                  setSheet(() {
                    row.amount -= 1;
                    row.qtyCtrl.text = row.amount.toStringAsFixed(1);
                  });
                }
              },
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 60,
              child: TextField(
                controller: row.qtyCtrl,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.orange),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Colors.orange, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onTap: () => _selectAllField(row.qtyCtrl),
                onChanged: (v) => setSheet(
                  () => row.amount = double.tryParse(v) ?? row.amount,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _CircleBtn(
              icon: Icons.add,
              onTap: () => setSheet(() {
                row.amount += 1;
                row.qtyCtrl.text = row.amount.toStringAsFixed(1);
              }),
            ),
            const SizedBox(width: 6),
            const Text('الكمية', style: TextStyle(fontSize: 12)),
          ]),
        ],
      ),
    ),
  );
}
