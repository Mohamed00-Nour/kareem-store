import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Widgets/egypt_phone_field.dart';
import '../repositories/client_repository.dart';
import '../repositories/supplier_repository.dart';
import 'invoice_number_utils.dart';
import 'invoice_print_service.dart';
import 'sales_invoice_image_service.dart';
import 'whatsapp_share_channel.dart';

class WhatsappInvoiceShareService {
  static String buildInvoiceMessage(Map<String, dynamic> invoice) {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final supplierName = invoice['supplierName']?.toString().trim() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;
    final name = isSupplier ? supplierName : clientName;

    final invoiceNumber = invoice['invoiceNumber']?.toString() ?? '';
    final dateStr = _formatDate(invoice['date']);
    final previous = invoiceDynamicPreviousBalance(invoice);
    final total = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final discount = invoiceResolveDiscount(invoice);

    final balance = isSupplier
        ? invoiceSupplierRemainingOwed(invoice)
        : invoiceClientRemainingOwed(invoice);

    final buffer = StringBuffer();
    if (name.isNotEmpty) {
      buffer.writeln(name);
    }
    final isBuyingReturn = invoiceIsBuyingReturn(invoice);
    if (isBuyingReturn) {
      buffer.writeln('مرتجع مشتريات رقم $invoiceNumber');
    } else if (isSupplier) {
      buffer.writeln('فاتورة مشتريات رقم $invoiceNumber');
    } else {
      buffer.writeln('فاتورة رقم $invoiceNumber');
    }
    buffer.writeln('التاريخ: $dateStr');
    buffer.writeln('الرصيد السابق: ${invoiceAmount(previous)} ج.م');
    buffer.writeln('إجمالي الفاتورة: ${invoiceAmount(total)} ج.م');
    if (discount > 0) {
      buffer.writeln('الخصم: ${invoiceAmount(discount)} ج.م');
    }
    buffer.writeln(isBuyingReturn
        ? 'المسترد من المورد: ${invoiceAmount(paid)} ج.م'
        : 'المدفوع: ${invoiceAmount(paid)} ج.م');
    buffer.writeln('المتبقي من الفاتورة: ${invoiceAmount(total - paid)} ج.م');
    if (isSupplier) {
      buffer.writeln('الرصيد الحالي للمورد: ${invoiceAmount(balance)} ج.م');
    } else {
      buffer.writeln('المتبقي عليكم: ${invoiceAmount(balance)} ج.م');
    }
    return buffer.toString().trim();
  }

  static Future<String?> fetchClientPhone(String clientName) async {
    final name = clientName.trim();
    if (name.isEmpty) return null;

    // 1. Try local Hive first (instant, 0ms)
    final localClient = ClientRepository.instance.findByName(name);
    if (localClient != null && localClient.phone.isNotEmpty) {
      return localClient.phone;
    }

    // 2. Fallback to Firestore
    try {
      final firestore = FirebaseFirestore.instance;

      final byDocId = await firestore.collection('clients').doc(name).get();
      if (byDocId.exists) {
        final phone = _readPhone(byDocId.data());
        if (phone != null) return phone;
      }

      final query = await firestore
          .collection('clients')
          .where('clientName', isEqualTo: name)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return _readPhone(query.docs.first.data());
      }
    } catch (_) {
      // Offline — no phone available
    }

    return null;
  }

  static Future<void> saveClientPhone(
      String clientName, String localPart) async {
    final name = clientName.trim();
    if (name.isEmpty) return;
    final phone = EgyptPhoneField.toWhatsappDigits(localPart);
    if (phone.isEmpty) return;

    final query = await FirebaseFirestore.instance
        .collection('clients')
        .where('clientName', isEqualTo: name)
        .limit(1)
        .get();

    DocumentReference docRef;
    if (query.docs.isNotEmpty) {
      docRef = query.docs.first.reference;
    } else {
      docRef = FirebaseFirestore.instance.collection('clients').doc();
    }

    await docRef.set(
      {'phone': phone, 'clientName': name, 'id': docRef.id},
      SetOptions(merge: true),
    );
  }

  /// Opens WhatsApp. With [phoneDigits] opens that chat; otherwise the user picks a contact.
  static Future<bool> openWhatsappChat({
    String? phoneDigits,
    required String message,
  }) async {
    final phone = phoneDigits?.replaceAll(RegExp(r'\D'), '') ?? '';
    final encoded = Uri.encodeComponent(message);
    final uris = phone.isNotEmpty
        ? [
            Uri.parse('https://wa.me/$phone?text=$encoded'),
            Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
          ]
        : [
            Uri.parse('https://wa.me/?text=$encoded'),
            Uri.parse('whatsapp://send?text=$encoded'),
          ];

    for (final uri in uris) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Phone digits for a share [choice]: the saved client/supplier number,
  /// a typed Egyptian number, or '' to let the user pick a WhatsApp contact.
  /// Null when the typed number is not valid.
  static String? recipientPhone(
    ShareRecipientChoice choice, {
    String? savedPhone,
    String typedNumber = '',
  }) {
    switch (choice) {
      case ShareRecipientChoice.saved:
        return savedPhone ?? '';
      case ShareRecipientChoice.other:
        return EgyptPhoneField.isValidLocalPart(typedNumber)
            ? EgyptPhoneField.toWhatsappDigits(typedNumber)
            : null;
      case ShareRecipientChoice.contactPicker:
        return '';
    }
  }

  /// Bottom sheet: choose who receives the invoice (the saved client or
  /// supplier number, another number, or a WhatsApp contact), then share it
  /// as text or as images. A typed number is used for this share only and is
  /// never saved on the client or supplier.
  static Future<void> showShareOptions(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
  }) async {
    final supplierName = invoice['supplierName']?.toString().trim() ?? '';
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;
    final name = isSupplier ? supplierName : clientName;
    if (name.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الاسم غير متوفر في الفاتورة')),
        );
      }
      return;
    }

    // The sheet opens at once; a client's number may still be loading.
    final savedPhoneFuture = isSupplier
        ? Future<String?>.value(supplierPhone(invoice))
        : fetchClientPhone(name).catchError((_) => null);
    ShareRecipientChoice? choice;
    final otherCtrl = TextEditingController();
    String? otherError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<String?>(
          future: savedPhoneFuture,
          builder: (ctx, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final savedPhone =
                (snapshot.data ?? '').isEmpty ? null : snapshot.data;
            return StatefulBuilder(builder: (ctx, setSheet) {
              final selected = choice ??
                  (savedPhone != null
                      ? ShareRecipientChoice.saved
                      : ShareRecipientChoice.contactPicker);

              Future<void> share({required bool asImage}) async {
                final phone = recipientPhone(
                  selected,
                  savedPhone: savedPhone,
                  typedNumber: otherCtrl.text,
                );
                if (phone == null) {
                  setSheet(() => otherError = 'يرجى إدخال رقم هاتف صحيح');
                  return;
                }
                Navigator.pop(ctx);
                if (asImage) {
                  await shareAsImage(
                    context,
                    invoice: invoice,
                    onShareSuccess: onShareSuccess,
                    phoneDigits: phone,
                  );
                } else {
                  await shareAsTextMessage(
                    context,
                    invoice: invoice,
                    onShareSuccess: onShareSuccess,
                    phoneDigits: phone,
                  );
                }
              }

              Widget option(ShareRecipientChoice value, String title,
                      {String? subtitle}) =>
                  RadioListTile<ShareRecipientChoice>(
                    value: value,
                    groupValue: selected,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(title),
                    subtitle: subtitle == null
                        ? null
                        : Text(subtitle, textDirection: TextDirection.ltr),
                    onChanged: (v) => setSheet(() {
                      choice = v;
                      otherError = null;
                    }),
                  );

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'مشاركة في واتساب',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'إرسال إلى:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (loading) const LinearProgressIndicator(),
                        if (savedPhone != null)
                          option(
                            ShareRecipientChoice.saved,
                            isSupplier ? 'رقم المورد' : 'رقم العميل',
                            subtitle:
                                '0${EgyptPhoneField.toLocalPartForInput(savedPhone)}',
                          ),
                        option(ShareRecipientChoice.other, 'رقم آخر'),
                        if (selected == ShareRecipientChoice.other) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: EgyptPhoneField(
                              controller: otherCtrl,
                              autofocus: true,
                              labelText: 'رقم المستلم',
                            ),
                          ),
                          if (otherError != null)
                            Text(
                              otherError!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                        ],
                        option(
                          ShareRecipientChoice.contactPicker,
                          'اختيار جهة اتصال من واتساب',
                        ),
                        const Divider(height: 24),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child:
                                Icon(Icons.chat, color: Colors.green.shade700),
                          ),
                          title: const Text('رسالة نصية'),
                          subtitle:
                              const Text('إرسال بيانات الفاتورة كنص في واتساب'),
                          onTap: () => share(asImage: false),
                        ),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade50,
                            child:
                                Icon(Icons.image, color: Colors.blue.shade700),
                          ),
                          title: const Text('صورة الفاتورة'),
                          subtitle: const Text(
                              'إرسال تفاصيل الفاتورة كصورة (أو عدة صور إن كانت طويلة)'),
                          onTap: () => share(asImage: true),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            });
          },
        ),
      ),
    );
  }

  /// [phoneDigits] overrides the saved number; '' lets the user pick a
  /// WhatsApp contact.
  static Future<void> shareAsTextMessage(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
    String? phoneDigits,
  }) async {
    final supplierName = invoice['supplierName']?.toString().trim() ?? '';
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;
    final name = isSupplier ? supplierName : clientName;
    if (name.isEmpty) return;

    final phone = phoneDigits ??
        (isSupplier ? supplierPhone(invoice) : await fetchClientPhone(name));

    final prepared = await InvoicePrintService.prepareForPrint(invoice,
        clientId: isSupplier ? null : name);
    final message = buildInvoiceMessage(prepared);
    final ok = await openWhatsappChat(
      phoneDigits: phone,
      message: message,
    );

    if (ok) {
      onShareSuccess?.call();
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر فتح واتساب. تأكد من تثبيت التطبيق'),
      ),
    );
  }

  /// [phoneDigits] overrides the saved number; '' lets the user pick a
  /// WhatsApp contact.
  static Future<void> shareAsImage(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
    String? phoneDigits,
  }) async {
    final supplierName = invoice['supplierName']?.toString().trim() ?? '';
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final isSupplier = supplierName.isNotEmpty && clientName.isEmpty;
    final name = isSupplier ? supplierName : clientName;
    if (name.isEmpty) return;

    final phone = phoneDigits ??
        (isSupplier ? supplierPhone(invoice) : await fetchClientPhone(name));

    if (!context.mounted) return;
    BuildContext? loadingDialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        loadingDialogContext = dialogCtx;
        return const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('جاري تجهيز صور الفاتورة...'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    var ok = false;
    try {
      final prepared = await InvoicePrintService.prepareForPrint(invoice,
          clientId: isSupplier ? null : name);
      final imageFiles =
          await SalesInvoiceImageService.generatePngPages(prepared);
      final caption = buildInvoiceMessage(prepared);
      ok = await WhatsappShareChannel.shareImages(
        phoneDigits: phone ?? '',
        imagePaths: imageFiles.map((f) => f.path).toList(),
        caption: caption,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء الصورة: $e')),
        );
      }
      return;
    } finally {
      final loadingCtx = loadingDialogContext;
      if (loadingCtx != null && loadingCtx.mounted) {
        Navigator.of(loadingCtx).pop();
      }
    }

    if (ok) {
      onShareSuccess?.call();
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر فتح واتساب. تأكد من تثبيت التطبيق'),
      ),
    );
  }

  /// The invoice supplier's saved WhatsApp number from the local cache, or
  /// null when the supplier has no phone (WhatsApp then asks for a contact).
  static String? supplierPhone(Map<String, dynamic> invoice) {
    final id = invoice['supplierId']?.toString().trim() ?? '';
    final name = invoice['supplierName']?.toString().trim() ?? '';
    final supplier = (id.isNotEmpty
            ? SupplierRepository.instance.getById(id)
            : null) ??
        (name.isNotEmpty ? SupplierRepository.instance.findByName(name) : null);
    return _readPhone(supplier == null ? null : {'phone': supplier.phone});
  }

  static String? _readPhone(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['phone']?.toString() ??
        data['clientPhone']?.toString() ??
        data['whatsapp']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return EgyptPhoneField.toWhatsappDigits(raw);
  }

  static String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      if (date is Timestamp) {
        return date.toDate().toLocal().toString().split(' ')[0];
      }
      if (date is DateTime) {
        return date.toLocal().toString().split(' ')[0];
      }
    } catch (_) {}
    final text = date.toString();
    if (text.length >= 10) return text.substring(0, 10);
    return text;
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

/// Who receives a shared invoice.
enum ShareRecipientChoice {
  /// The number saved on the client or supplier.
  saved,

  /// A number typed for this share only (never saved).
  other,

  /// WhatsApp's own contact picker.
  contactPicker,
}
