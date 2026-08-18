import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kareem_store/Widgets/egypt_phone_field.dart';
import 'package:kareem_store/Services/invoice_number_utils.dart';
import 'bloc/invoice_cubit.dart';
import 'bloc/invoice_state.dart';

class ClientSelectionResult {
  final String clientName;
  final double clientBalance;
  final String paidAmountText;
  ClientSelectionResult({
    required this.clientName,
    required this.clientBalance,
    required this.paidAmountText,
  });
}

void showClientNameDialog(
  BuildContext context,
  String initialClientName,
  String initialPaidAmountText,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
    builder: (ctx) {
      return BlocProvider.value(
        value: BlocProvider.of<InvoiceCubit>(context),
        child: _ClientSelectionContent(
          initialClientName: initialClientName,
          initialPaidAmountText: initialPaidAmountText,
        ),
      );
    },
  ).then((result) {
    if (result is ClientSelectionResult && context.mounted) {
      BlocProvider.of<InvoiceCubit>(context).setClientInfo(
            result.clientName,
            result.clientBalance,
            result.paidAmountText,
          );
    }
  });
}

class _ClientSelectionContent extends StatefulWidget {
  final String initialClientName;
  final String initialPaidAmountText;
  const _ClientSelectionContent({
    required this.initialClientName,
    required this.initialPaidAmountText,
  });

  @override
  State<_ClientSelectionContent> createState() => _ClientSelectionContentState();
}

class _ClientSelectionContentState extends State<_ClientSelectionContent> {
  String searchQuery = '';
  bool showAddField = false;
  String? duplicateWarning;
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController newClientCtrl = TextEditingController();
  final TextEditingController newClientBalanceCtrl = TextEditingController();
  final TextEditingController newClientPhoneCtrl = TextEditingController();
  late final TextEditingController localPaidCtrl;
  late String selectedClient;
  double? selectedClientBalance;
  bool loadingClientBalance = false;
  bool addingNewClient = false;

  @override
  void initState() {
    super.initState();
    localPaidCtrl = TextEditingController(text: widget.initialPaidAmountText);
    selectedClient = widget.initialClientName;
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    newClientCtrl.dispose();
    newClientBalanceCtrl.dispose();
    newClientPhoneCtrl.dispose();
    localPaidCtrl.dispose();
    super.dispose();
  }

  Future<void> loadDialogClientBalance(String clientName) async {
    if (clientName.trim().isEmpty) {
      setState(() {
        selectedClientBalance = null;
        loadingClientBalance = false;
      });
      return;
    }
    setState(() {
      loadingClientBalance = true;
      selectedClientBalance = null;
    });
    final bal = await BlocProvider.of<InvoiceCubit>(context).fetchClientBalance(clientName.trim());
    if (!mounted) return;
    setState(() {
      selectedClientBalance = bal;
      loadingClientBalance = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InvoiceCubit, InvoiceState>(
      builder: (context, state) {
        if (selectedClient.isNotEmpty &&
            selectedClientBalance == null &&
            !loadingClientBalance) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            loadDialogClientBalance(selectedClient);
          });
        }
        final filtered = searchQuery.isEmpty
            ? state.clients
            : state.clients
                .where((c) =>
                    c.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20.h,
              left: 16.w,
              right: 16.w,
              top: 20.h,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'اختر العميل',
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),

                // ── Search + Add button ──
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          hintText: 'ابحث عن عميل...',
                          hintTextDirection: TextDirection.rtl,
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.black54),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.black54),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setState(() => searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 10.h),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.r),
                            borderSide:
                                BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.r),
                            borderSide:
                                BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.r),
                            borderSide:
                                const BorderSide(color: Colors.black87),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (v) =>
                            setState(() => searchQuery = v.trim()),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Tooltip(
                      message: 'إضافة عميل جديد',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10.r),
                        onTap: () =>
                            setState(() => showAddField = !showAddField),
                        child: Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: showAddField
                                ? Colors.black87
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(
                            Icons.person_add_alt_1,
                            color:
                                showAddField ? Colors.white : Colors.black87,
                            size: 22.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Add new client inline field ──
                if (showAddField) ...[
                  SizedBox(height: 10.h),
                  TextField(
                    controller: newClientCtrl,
                    textDirection: TextDirection.rtl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'اسم العميل الجديد *',
                      hintTextDirection: TextDirection.rtl,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: newClientBalanceCtrl,
                    textDirection: TextDirection.rtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'الرصيد الافتتاحي (اختياري)',
                      hintTextDirection: TextDirection.rtl,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  EgyptPhoneField(
                    controller: newClientPhoneCtrl,
                    hintText: '1xxxxxxxxx (اختياري)',
                  ),
                  SizedBox(height: 8.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      onPressed: addingNewClient
                          ? null
                          : () async {
                              final newName = newClientCtrl.text.trim();
                              if (newName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('يرجى إدخال اسم العميل'),
                                  ),
                                );
                                return;
                              }
                              final phoneText =
                                  newClientPhoneCtrl.text.trim();
                              if (phoneText.isNotEmpty &&
                                  !EgyptPhoneField.isValidLocalPart(
                                      phoneText)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'يرجى إدخال رقم هاتف صحيح بعد +20'),
                                  ),
                                );
                                return;
                              }
                              final alreadyExists = state.clients.any((c) =>
                                  c.toLowerCase() == newName.toLowerCase());
                              if (alreadyExists) {
                                setState(() {
                                  duplicateWarning =
                                      'هذا العميل موجود بالفعل';
                                  selectedClient = state.clients.firstWhere((c) =>
                                      c.toLowerCase() ==
                                      newName.toLowerCase());
                                });
                                return;
                              }

                              setState(() {
                                addingNewClient = true;
                                duplicateWarning = null;
                              });
                              try {
                                final balanceText =
                                    newClientBalanceCtrl.text.trim();
                                final balance = balanceText.isEmpty
                                    ? 0.0
                                    : (double.tryParse(balanceText) ?? 0.0);
                                
                                await BlocProvider.of<InvoiceCubit>(context).addNewClient(newName, balance, phoneText);

                                if (!mounted) return;
                                setState(() {
                                  selectedClient = newName;
                                  selectedClientBalance = balance;
                                  showAddField = false;
                                  newClientCtrl.clear();
                                  newClientBalanceCtrl.clear();
                                  newClientPhoneCtrl.clear();
                                });
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('خطأ أثناء إضافة العميل: $e'),
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => addingNewClient = false);
                                }
                              }
                            },
                      child: addingNewClient
                          ? SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('إضافة العميل',
                              style: TextStyle(fontSize: 13.sp)),
                    ),
                  ),
                ],
                // ── Duplicate warning ──
                if (duplicateWarning != null) ...[
                  SizedBox(height: 8.h),
                  Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8.r),
                      border:
                          Border.all(color: Colors.orange.shade300, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange.shade700, size: 16.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            duplicateWarning!,
                            style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 10.h),

                // ── Client list ──
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.30),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          child: Text(
                            'لا يوجد عميل بهذا الاسم',
                            style: TextStyle(
                                fontSize: 13.sp, color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final client = filtered[i];
                            final isSelected = client == selectedClient;
                            return InkWell(
                              onTap: () {
                                setState(() => selectedClient = client);
                                loadDialogClientBalance(client);
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12.w, vertical: 10.h),
                                margin: EdgeInsets.symmetric(vertical: 3.h),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.black87
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 18.sp,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black54,
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(
                                      child: Text(
                                        client,
                                        style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle,
                                          size: 18.sp, color: Colors.orange),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Divider(height: 20.h),

                if (selectedClient.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                        horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10.r),
                      border:
                          Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: loadingClientBalance
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'جاري تحميل الرصيد...',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          )
                        : Text(
                            'الرصيد الحالي: ${invoiceAmount(selectedClientBalance ?? 0)} ج.م',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                              color: (selectedClientBalance ?? 0) > 0
                                  ? Colors.red.shade700
                                  : Colors.black87,
                            ),
                          ),
                  ),
                  SizedBox(height: 12.h),
                ],

                // ── المبلغ المدفوع ──
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'المبلغ المدفوع',
                    style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
                SizedBox(height: 6.h),
                TextField(
                  controller: localPaidCtrl,
                  textDirection: TextDirection.rtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: const Icon(Icons.payments_outlined,
                        color: Colors.black54),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12.w, vertical: 10.h),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide:
                          const BorderSide(color: Colors.black87, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                SizedBox(height: 14.h),

                // ── Confirm button ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                    ),
                    onPressed: selectedClient.isEmpty
                        ? null
                        : () async {
                            final bal = await BlocProvider.of<InvoiceCubit>(context).fetchClientBalance(
                              selectedClient.trim(),
                            );
                            if (!mounted) return;
                            Navigator.of(context).pop(ClientSelectionResult(
                              clientName: selectedClient,
                              clientBalance: bal,
                              paidAmountText: localPaidCtrl.text,
                            ));
                          },
                    child: Text('تأكيد',
                        style: TextStyle(
                            fontSize: 15.sp, fontWeight: FontWeight.bold)),
                  ),
                ),
                SizedBox(height: 20.h),
              ],
            ),
          ),
        );
      },
    );
  }
}
