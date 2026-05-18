import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Widgets/egypt_phone_field.dart';
import 'invoice_print_service.dart';
import 'sales_invoice_image_service.dart';
import 'whatsapp_share_channel.dart';

class WhatsappInvoiceShareService {
  static String buildInvoiceMessage(Map<String, dynamic> invoice) {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    final invoiceNumber = invoice['invoiceNumber']?.toString() ?? '';
    final dateStr = _formatDate(invoice['date']);
    final total = _num(invoice['totalSum']);
    final paid = _num(invoice['paidAmount']);
    final balance = _num(invoice['balance']);

    final buffer = StringBuffer();
    if (clientName.isNotEmpty) {
      buffer.writeln(clientName);
    }
    buffer.writeln('عليكم فاتورة آجل رقم $invoiceNumber');
    buffer.writeln('التاريخ $dateStr');
    buffer.writeln('بإجمالي ${total.toStringAsFixed(2)} ج.م');
    buffer.writeln('المدفوع ${paid.toStringAsFixed(2)} ج.م');
    buffer.writeln(
        'الرصيد الحالي عليكم ${balance.toStringAsFixed(2)} ج.م');
    return buffer.toString().trim();
  }

  static Future<String?> fetchClientPhone(String clientName) async {
    final name = clientName.trim();
    if (name.isEmpty) return null;

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

    return null;
  }

  static Future<void> saveClientPhone(String clientName, String localPart) async {
    final name = clientName.trim();
    if (name.isEmpty) return;
    final phone = EgyptPhoneField.toWhatsappDigits(localPart);
    if (phone.isEmpty) return;

    await FirebaseFirestore.instance.collection('clients').doc(name).set(
      {'phone': phone, 'clientName': name},
      SetOptions(merge: true),
    );
  }

  static Future<bool> openWhatsappChat({
    required String phoneDigits,
    required String message,
  }) async {
    final phone = phoneDigits.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return false;

    final encoded = Uri.encodeComponent(message);
    final uris = [
      Uri.parse('https://wa.me/$phone?text=$encoded'),
      Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
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

  /// Bottom sheet: share invoice as WhatsApp text to the client's chat.
  static Future<void> showShareOptions(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
  }) async {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    if (clientName.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم العميل غير متوفر في الفاتورة')),
        );
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'مشاركة في واتساب',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  clientName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade50,
                    child: Icon(Icons.chat, color: Colors.green.shade700),
                  ),
                  title: const Text('رسالة نصية'),
                  subtitle: const Text('إرسال بيانات الفاتورة كنص في واتساب'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await shareAsTextMessage(
                      context,
                      invoice: invoice,
                      onShareSuccess: onShareSuccess,
                    );
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(Icons.image, color: Colors.blue.shade700),
                  ),
                  title: const Text('صورة الفاتورة'),
                  subtitle: const Text(
                      'إرسال تفاصيل الفاتورة كاملة كصورة في واتساب'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await shareAsImage(
                      context,
                      invoice: invoice,
                      onShareSuccess: onShareSuccess,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> shareAsTextMessage(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
  }) async {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    if (clientName.isEmpty) return;

    final phone = await _resolveClientPhone(context, clientName);
    if (phone == null || phone.isEmpty) return;

    final prepared =
        await InvoicePrintService.prepareForPrint(invoice, clientId: clientName);
    final message = buildInvoiceMessage(prepared);
    final ok = await openWhatsappChat(phoneDigits: phone, message: message);

    if (ok) {
      onShareSuccess?.call();
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'تعذر فتح واتساب. تأكد من تثبيت التطبيق ورقم الهاتف'),
      ),
    );
  }

  static Future<void> shareAsImage(
    BuildContext context, {
    required Map<String, dynamic> invoice,
    VoidCallback? onShareSuccess,
  }) async {
    final clientName = invoice['clientName']?.toString().trim() ?? '';
    if (clientName.isEmpty) return;

    final phone = await _resolveClientPhone(context, clientName);
    if (phone == null || phone.isEmpty) return;

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
                    Text('جاري تجهيز صورة الفاتورة...'),
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
      final prepared =
          await InvoicePrintService.prepareForPrint(invoice, clientId: clientName);
      final imageFile = await SalesInvoiceImageService.generatePng(prepared);
      final caption = buildInvoiceMessage(prepared);
      ok = await WhatsappShareChannel.shareImage(
        phoneDigits: phone,
        imagePath: imageFile.path,
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

  static Future<String?> _resolveClientPhone(
    BuildContext context,
    String clientName,
  ) async {
    var phone = await fetchClientPhone(clientName);
    if (phone == null || phone.isEmpty) {
      if (!context.mounted) return null;
      phone = await _promptForPhone(context, clientName);
    }
    return phone;
  }

  static Future<String?> _promptForPhone(
    BuildContext context,
    String clientName,
  ) async {
    final localCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('رقم واتساب العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('أدخل رقم $clientName لمشاركة الفاتورة'),
              const SizedBox(height: 12),
              EgyptPhoneField(controller: localCtrl, autofocus: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!EgyptPhoneField.isValidLocalPart(localCtrl.text)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('رقم غير صحيح')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return null;
    final digits = EgyptPhoneField.toWhatsappDigits(localCtrl.text);
    await saveClientPhone(clientName, localCtrl.text);
    return digits;
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
