// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
//
// import '../DeletedClientsPage.dart';
// import 'ClientInvoicesPage.dart';
//
// class ClientsPage extends StatefulWidget {
//   const ClientsPage({Key? key}) : super(key: key);
//
//   @override
//   _ClientsPageState createState() => _ClientsPageState();
// }
//
// class _ClientsPageState extends State<ClientsPage> {
//   String _searchQuery = '';
//   final Set<String> _deletedClients = {}; // Track deleted client IDs
//   void _showDeleteConfirmationDialog(String clientId) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('تأكيد الحذف'),
//         content: const Text('هل تريد حذف هذا العميل من القائمة؟'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('لا'),
//           ),
//           TextButton(
//             onPressed: () {
//               setState(() {
//                 _deletedClients.add(clientId); // Add client ID to deleted list
//               });
//               Navigator.pop(context);
//             },
//             child: const Text('نعم'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.delete, color: Colors.white),
//             onPressed: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => DeletedClientsPage(
//                     deletedClients: _deletedClients,
//                     onRestoreClient: (clientId) {
//                       setState(() {
//                         _deletedClients.remove(clientId); // Remove client ID from deleted list
//                       });
//                     },
//                   ),
//                 ),
//               );
//             },
//           ),
//         ],
//         backgroundColor: Colors.black.withOpacity(0.7),
//         title: const Text('العملاء' , style: TextStyle(
//           color: Colors.white,
//           fontSize: 20,
//           fontWeight: FontWeight.bold,
//         )),
//       ),
//       body: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
//             child: TextField(
//               decoration: InputDecoration(
//                 focusedBorder: OutlineInputBorder(
//                   borderSide:  BorderSide(color: Colors.black.withOpacity(0.7)),
//                 ),
//                 filled: true,
//                 fillColor: Colors.grey.withOpacity(0.1),
//                 labelText: 'ابحث عن عميل',
//                 labelStyle:  TextStyle(
//                   color: Colors.black.withOpacity(0.7),
//                   fontSize:18,
//                 ),
//                 border: OutlineInputBorder(
//                   borderSide: BorderSide(
//                     color: Colors.black.withOpacity(0.7),
//                   )
//                 ),
//                 prefixIcon: Icon(Icons.search),
//               ),
//               onChanged: (query) {
//                 setState(() {
//                   _searchQuery = query;
//                 });
//               },
//             ),
//           ),
//           Expanded(
//             child: StreamBuilder<QuerySnapshot>(
//               stream: FirebaseFirestore.instance.collection('clients').snapshots(),
//               builder: (context, snapshot) {
//                 if (!snapshot.hasData) {
//                   return  Center(child: CircularProgressIndicator(
//                     color: Colors.black.withOpacity(0.7),
//                   ));
//                 }
//
//                 final allClients = snapshot.data!.docs;
//                 final filteredClients = _searchQuery.isEmpty
//                     ? allClients
//                     : allClients.where((client) {
//                         final clientName = client['clientName']?.toString().toLowerCase() ?? '';
//                         return clientName.contains(_searchQuery.toLowerCase());
//                       }).toList();
//                 final visibleClients = filteredClients.where((client) => !_deletedClients.contains(client.id)).toList();
//
//                 return ListView.builder(
//                   itemCount: visibleClients.length,
//                   itemBuilder: (context, index) {
//                     final client = visibleClients[index];
//                     return Card(
//                       elevation: 2,
//                       color: Colors.orange.withOpacity(0.7),
//                       margin: const EdgeInsets.all(10.0),
//                       child: ListTile(
//                         title: Center(child: Text(client['clientName'])),
//                         subtitle: Center(child: Text('الرصيد: ${client['balance'].toStringAsFixed(2)}')),
//                         onTap: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(
//                               builder: (context) => ClientInvoicesPage(clientId: client.id),
//                             ),
//                           );
//                         },
//                         onLongPress: () {
//                           _showDeleteConfirmationDialog(client.id);
//                         },
//                       ),
//                     );
//                   },
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../DeletedClientsPage.dart';
import '../Services/party_rename_service.dart';
import '../Widgets/egypt_phone_field.dart';
import '../Widgets/app_responsive.dart';
import 'ClientInvoicesPage.dart';
import '../Services/client_invoice_balance_sync_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../Services/whatsapp_invoice_share_service.dart';
import '../sync/connectivity_service.dart';
import '../repositories/client_repository.dart';
import '../repositories/balance_history_repository.dart';
import '../repositories/box_repository.dart';
import '../local_db/models/balance_history_local.dart';
import '../sync/sync_queue_manager.dart';

// ─── Main Menu Page ──────────────────────────────────────────────────────────

class ClientsPage extends StatelessWidget {
  const ClientsPage({Key? key}) : super(key: key);

  void _addNewClient(BuildContext context) {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (dialogCtx, setDialogState) => AlertDialog(
            title: const Text('إضافة عميل جديد'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'اسم العميل'),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: balanceCtrl,
                    enabled: !isSaving,
                    decoration:
                        const InputDecoration(labelText: 'الرصيد الافتتاحي'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  EgyptPhoneField(
                    controller: phoneCtrl,
                    labelText: 'رقم الهاتف (واتساب) - اختياري',
                  ),
                  if (isSaving) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.7)),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        // Capture messenger before any await to avoid BuildContext-across-async-gap lint.
                        final messenger = ScaffoldMessenger.of(ctx);
                        if (name.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('يرجى إدخال اسم العميل')),
                          );
                          return;
                        }

                        // ── Duplicate-name check against local Hive ───────────────
                        final existing =
                            ClientRepository.instance.findByName(name);
                        if (existing != null) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('يوجد عميل بهذا الاسم بالفعل')),
                          );
                          return;
                        }

                        // ── Phone validation ──────────────────────────────────────
                        final phoneLocal = phoneCtrl.text.trim();
                        if (phoneLocal.isNotEmpty &&
                            !EgyptPhoneField.isValidLocalPart(
                                phoneCtrl.text)) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'رقم الهاتف غير صحيح. اتركه فارغاً أو أدخل رقماً صالحاً'),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);

                        try {
                          final balance =
                              double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                          final docRef = FirebaseFirestore.instance
                              .collection('clients')
                              .doc();
                          final clientId = docRef.id;

                          final data = <String, dynamic>{
                            'clientName': name,
                            'balance': balance,
                            'id': clientId,
                          };
                          if (phoneLocal.isNotEmpty) {
                            data['phone'] = EgyptPhoneField.toWhatsappDigits(
                                phoneCtrl.text);
                          }

                          // ── 1. Save to local Hive database immediately (0ms) ─────
                          await ClientRepository.instance
                              .upsertLocal(clientId, data);

                          if (balance != 0) {
                            await BalanceHistoryRepository.instance.upsertLocal(
                              BalanceHistoryLocal(
                                id: '${clientId}_opening',
                                parentId: clientId,
                                parentType: 'client',
                                enteredBalance: balance,
                                balanceBefore: 0.0,
                                type: 'opening',
                                timestamp: DateTime.now(),
                              ),
                            );
                          }

                          // ── 2. Close dialog immediately — Hive is our primary DB ─
                          if (ctx.mounted) Navigator.pop(ctx);

                          // ── 3. Sync to Firestore in background (non-blocking) ─────
                          final bool isOnline =
                              ConnectivityService.instance.isOnline;
                          if (isOnline) {
                            // Fire-and-forget: don't await, don't block
                            Future(() async {
                              try {
                                await docRef.set(data, SetOptions(merge: true));
                                if (balance != 0) {
                                  await docRef
                                      .collection('balanceHistory')
                                      .doc('${clientId}_opening')
                                      .set({
                                    'enteredBalance': balance,
                                    'balanceBefore': 0.0,
                                    'type': 'opening',
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });
                                }
                              } catch (_) {
                                // If Firestore fails, enqueue for retry
                                await SyncQueueManager.instance.enqueue(
                                  operationType: 'createClient',
                                  payload: {
                                    'clientId': clientId,
                                    'data': data,
                                    'openingBalance': balance
                                  },
                                );
                              }
                            });
                          } else {
                            await SyncQueueManager.instance.enqueue(
                              operationType: 'createClient',
                              payload: {
                                'clientId': clientId,
                                'data': data,
                                'openingBalance': balance
                              },
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('حفظ', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
        label: 'اضافة عميل جديد',
        icon: Icons.add,
        iconColor: Colors.green,
        onTap: () => _addNewClient(context),
      ),
      _MenuItem(
        label: 'الأرصدة الافتتاحيه والمبالغ النقدية للعملاء',
        customIcon: const Icon(Icons.settings, color: Colors.grey),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const _ClientOpeningBalancesPage())),
      ),
      _MenuItem(
        label: 'ذمم العملاء - المبالغ المتبقية عند العملاء من الفواتير الآجل',
        icon: Icons.people,
        iconColor: Colors.brown,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _ClientDeferredPage())),
      ),
      _MenuItem(
        label: 'ذمم العملاء - تقرير',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const _ClientRemainingReportPage())),
      ),
      _MenuItem(
        label: 'العملاء المتبقي لهم أرصدة - تقرير',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const _ClientBalanceReportPage())),
      ),
      _MenuItem(
        label: 'فحص ارصدة العملاء',
        icon: Icons.receipt_long,
        iconColor: Colors.black54,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _ClientBalanceCheckPage())),
      ),
      _MenuItem(
        label: 'عرض العملاء',
        icon: Icons.search,
        iconColor: Colors.black54,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _ClientListPage())),
      ),
    ];

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: const Text(
            'العملاء',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.shade300),
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: item.onTap,
              child: Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    item.customIcon ??
                        Icon(item.icon, color: item.iconColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Widget? customIcon;
  final VoidCallback onTap;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.customIcon,
  });
}

/// Shared card for client / supplier list grids (two per row).
class _PartyInfoCard extends StatelessWidget {
  final String name;
  final double balance;
  final String phone;
  final bool isClient;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PartyInfoCard({
    required this.name,
    required this.balance,
    required this.phone,
    required this.isClient,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final balanceColor = balance > 0
        ? Colors.red.shade700
        : balance < 0
            ? Colors.green.shade700
            : Colors.black87;

    return Card(
      elevation: 3,
      color: Colors.orange.withOpacity(0.75),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isClient ? Icons.person_outline : Icons.store_outlined,
                size: 32,
                color: Colors.black.withOpacity(0.65),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'الرصيد',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
              Text(
                balance.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: balanceColor,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone,
                        size: 14, color: Colors.black.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        phone,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'اضغط للفواتير • اضغط مطولاً للخيارات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black.withOpacity(0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Opening Balances Page ───────────────────────────────────────────────────

class _ClientOpeningBalancesPage extends StatefulWidget {
  const _ClientOpeningBalancesPage();

  @override
  State<_ClientOpeningBalancesPage> createState() =>
      _ClientOpeningBalancesPageState();
}

class _ClientOpeningBalancesPageState
    extends State<_ClientOpeningBalancesPage> {
  String _search = '';
  bool _generating = false;
  Box<String>? _deletedClientsBox;

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    final box = Hive.isBoxOpen('deletedClients')
        ? Hive.box<String>('deletedClients')
        : await Hive.openBox<String>('deletedClients');
    if (mounted) {
      setState(() {
        _deletedClientsBox = box;
      });
    }
  }

  void _showReportChoiceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'اختر نوع التقرير',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                title: const Text('تقرير الأرصدة الافتتاحية والمبالغ النقدية'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf();
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('تقرير سند الصرف'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('عليه', 'تقرير سند الصرف');
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.green),
                title: const Text('تقرير سند القبض'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('له', 'تقرير سند القبض');
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.orange),
                title: const Text('عملاء عليهم أموال'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf(onlyWithBalanceOwed: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.teal),
                title: const Text('عملاء لهم أموال'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf(onlyWithBalanceCredit: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateVoucherPdf(String direction, String reportTitle) async {
    final voucherCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(reportTitle),
          content: TextField(
            controller: voucherCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رقم السند',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || voucherCtrl.text.trim().isEmpty) return;
    final voucherNumber = int.tryParse(voucherCtrl.text.trim());
    if (voucherNumber == null) return;

    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      final snap = await FirebaseFirestore.instance
          .collection('client_vouchers')
          .where('direction', isEqualTo: direction)
          .where('voucherNumber', isEqualTo: voucherNumber)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لم يتم العثور على سند برقم $voucherNumber')),
          );
        }
        return;
      }

      final data = snap.docs.first.data();
      final voucherDate = (data['date'] is Timestamp)
          ? DateFormat('yyyy/MM/dd')
              .format((data['date'] as Timestamp).toDate())
          : data['date']?.toString() ?? '';
      final clientName = (data['clientName'] ?? '').toString();
      final amount = (data['amount'] ?? 0.0).toDouble();
      final description = (data['description'] ?? '').toString();
      final vNum = data['voucherNumber']?.toString() ?? '';

      pw.TextStyle s(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 11}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.TableRow row3(String arabic, String english, String value) =>
          pw.TableRow(
            children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(english, style: s()),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(value,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                    style: s(bold: true)),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(arabic,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.right,
                    style: s(bold: true)),
              ),
            ],
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: s(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: s(fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('#$vNum#', style: s(fontSize: 12)),
                    pw.Text(
                      reportTitle,
                      textDirection: pw.TextDirection.rtl,
                      style: s(bold: true, fontSize: 16),
                    ),
                    pw.Text('ج.م', style: s(fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    row3('رقم السند', 'No.', vNum),
                    row3('التاريخ', 'Date', voucherDate),
                    row3('تم تسليم السيد/الساده', 'Pay To Mr/Mrs', clientName),
                    row3('مبلغ وقدره', 'Amount',
                        'فقط ${amount.toStringAsFixed(2)} ج.م لا غير'),
                    row3('وذلك مقابل', 'For', description),
                  ],
                ),
                pw.SizedBox(height: 60),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المدير',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المستلم',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeTitle = direction == 'عليه' ? 'sarf' : 'qabdh';
      final file = File(
          '${dir.path}/client_voucher_${safeTitle}_${vNum}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Text(reportTitle),
              content: const Text('تم إنشاء السند. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles([XFile(file.path)],
                        text: reportTitle);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء السند: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePdf({
    bool onlyWithBalanceOwed = false,
    bool onlyWithBalanceCredit = false,
  }) async {
    assert(!(onlyWithBalanceOwed && onlyWithBalanceCredit));
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      final snap = await FirebaseFirestore.instance.collection('clients').get();

      final reportTitle = onlyWithBalanceOwed
          ? 'عملاء عليهم أموال'
          : onlyWithBalanceCredit
              ? 'عملاء لهم أموال'
              : 'الأرصدة الافتتاحية والمبالغ النقدية للعملاء';

      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final docData = doc.data() as Map<String, dynamic>?;
        final name = (docData?['clientName'] ?? doc.id).toString().trim();
        if (name.isEmpty) continue;
        final balance = (docData?['balance'] ?? 0.0).toDouble();
        final lahu = balance < 0 ? balance.abs() : 0.0;
        final alayhi = balance > 0 ? balance : 0.0;
        if (onlyWithBalanceOwed) {
          if (balance <= 0) continue;
          rows.add({'name': name, 'amount': alayhi});
        } else if (onlyWithBalanceCredit) {
          if (balance >= 0) continue;
          rows.add({'name': name, 'amount': lahu});
        } else {
          rows.add({'name': name, 'lahu': lahu, 'alayhi': alayhi});
        }
      }

      rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('لا يوجد عملاء في $reportTitle')),
          );
        }
        return;
      }

      final filteredReport = onlyWithBalanceOwed || onlyWithBalanceCredit;
      final amountHeader =
          onlyWithBalanceOwed ? 'عليه' : (onlyWithBalanceCredit ? 'له' : '');
      final grandFiltered = filteredReport
          ? rows.fold<double>(0.0, (s, r) => s + (r['amount'] as double))
          : 0.0;
      final grandLahu = filteredReport
          ? 0.0
          : rows.fold<double>(0.0, (s, r) => s + (r['lahu'] as double));
      final grandAlayhi = filteredReport
          ? 0.0
          : rows.fold<double>(0.0, (s, r) => s + (r['alayhi'] as double));

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(bold: true, fontSize: 9)),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(
                    bold: bold, color: red ? PdfColors.red : PdfColors.black)),
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    reportTitle,
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                if (filteredReport)
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey400, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(4),
                      2: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          headerCell('#'),
                          headerCell('اسم العميل'),
                          headerCell(amountHeader),
                        ],
                      ),
                      for (int i = 0; i < rows.length; i++)
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color:
                                i.isEven ? PdfColors.white : PdfColors.grey50,
                          ),
                          children: [
                            dataCell('${i + 1}'),
                            dataCell(rows[i]['name'] as String),
                            dataCell(
                              (rows[i]['amount'] as double).toStringAsFixed(2),
                              bold: true,
                              red: onlyWithBalanceCredit,
                            ),
                          ],
                        ),
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey100),
                        children: [
                          dataCell(''),
                          dataCell('الإجمالي', bold: true, red: true),
                          dataCell(
                            grandFiltered.toStringAsFixed(2),
                            bold: true,
                            red: onlyWithBalanceCredit,
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey400, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          headerCell('#'),
                          headerCell('اسم العميل'),
                          headerCell('له'),
                          headerCell('عليه'),
                        ],
                      ),
                      for (int i = 0; i < rows.length; i++)
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color:
                                i.isEven ? PdfColors.white : PdfColors.grey50,
                          ),
                          children: [
                            dataCell('${i + 1}'),
                            dataCell(rows[i]['name'] as String),
                            dataCell(
                              (rows[i]['lahu'] as double).toStringAsFixed(2),
                              red: (rows[i]['lahu'] as double) > 0,
                            ),
                            dataCell(
                              (rows[i]['alayhi'] as double).toStringAsFixed(2),
                            ),
                          ],
                        ),
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey100),
                        children: [
                          dataCell(''),
                          dataCell('الإجمالي', bold: true, red: true),
                          dataCell(
                            grandLahu.toStringAsFixed(2),
                            bold: true,
                            red: true,
                          ),
                          dataCell(
                            grandAlayhi.toStringAsFixed(2),
                            bold: true,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileSuffix = onlyWithBalanceOwed
          ? 'owes'
          : onlyWithBalanceCredit
              ? 'credit'
              : 'all';
      final file = File(
          '${dir.path}/client_balances_${fileSuffix}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Text(reportTitle),
              content: const Text('تم إنشاء التقرير. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles([XFile(file.path)],
                        text: reportTitle);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showAddAmountDialog(BuildContext context, String clientId,
      String clientName, double currentBalance) async {
    int nextVoucher = 1;
    try {
      final voucherSnap = await FirebaseFirestore.instance
          .collection('client_vouchers')
          .orderBy('voucherNumber', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 3));
      if (voucherSnap.docs.isNotEmpty) {
        nextVoucher = (voucherSnap.docs.first['voucherNumber'] as int) + 1;
      }
    } catch (_) {
      nextVoucher = DateTime.now().millisecondsSinceEpoch % 10000;
    }

    if (!context.mounted) return;

    String direction = 'عليه';
    String paymentMethod = 'نقداً';
    DateTime selectedDate = DateTime.now();
    final amountCtrl = TextEditingController(text: '0');
    final descCtrl = TextEditingController();
    final voucherCtrl = TextEditingController(text: nextVoucher.toString());
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'اضف مبلغ للعميل',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        clientName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        color: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Row(children: [
                              Radio<String>(
                                value: 'عليه',
                                groupValue: direction,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => direction = v!),
                              ),
                              const Text('عليه',
                                  style: TextStyle(fontSize: 15)),
                            ]),
                            Row(children: [
                              Radio<String>(
                                value: 'له',
                                groupValue: direction,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => direction = v!),
                              ),
                              const Text('له', style: TextStyle(fontSize: 15)),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: voucherCtrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('رقم السند',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descCtrl,
                        textAlign: TextAlign.right,
                        enabled: !isSaving,
                        decoration: InputDecoration(
                          hintText: 'البيان : تفاصيل السند',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: isSaving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDlg(() => selectedDate = picked);
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('التاريخ',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 15)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Wrap(
                          alignment: WrapAlignment.spaceEvenly,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'شيك',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('شيك'),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'بطاقة',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('بطاقة'),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Radio<String>(
                                value: 'نقداً',
                                groupValue: paymentMethod,
                                activeColor: Colors.green,
                                onChanged: isSaving
                                    ? null
                                    : (v) => setDlg(() => paymentMethod = v!),
                              ),
                              const Text('نقداً'),
                            ]),
                            const Text('طريقة الدفع',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              enabled: !isSaving,
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isSaving
                                    ? Colors.grey.shade200
                                    : Colors.yellow.shade200,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('المبلغ',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text('تراجع',
                                style: TextStyle(
                                    color: Colors.pink, fontSize: 15)),
                          ),
                          TextButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final amount =
                                        double.tryParse(amountCtrl.text) ?? 0.0;
                                    if (amount == 0) return;

                                    setDlg(() => isSaving = true);

                                    final bool isOnline = ConnectivityService.instance.isOnline;
                                    final isAddition = direction == 'عليه';
                                    double delta = isAddition ? amount : -amount;

                                    // ── Unified local-first path (online & offline identical) ──
                                    // Write to Hive immediately, then enqueue for Firestore sync.
                                    // No syncForClient() call — that would trigger a full recalculation race.
                                    try {
                                      final clientLocal = ClientRepository
                                          .instance
                                          .getById(clientId);
                                      final double latestBalance =
                                          clientLocal?.balance ?? currentBalance;
                                      final double newBalance =
                                          latestBalance + delta;

                                      await ClientRepository.instance
                                          .updateLocalBalance(
                                              clientId, newBalance);

                                      final vNumber =
                                          int.tryParse(voucherCtrl.text) ??
                                              nextVoucher;
                                      String noteStr = 'سند $direction';
                                      noteStr += ' رقم $vNumber';
                                      final dText = descCtrl.text.trim();
                                      if (dText.isNotEmpty) {
                                        noteStr += ' ($dText)';
                                      }

                                      final historyId =
                                          DateTime.now().millisecondsSinceEpoch.toString();

                                      // ── Write balance history entry to Hive ──
                                      await BalanceHistoryRepository.instance
                                          .upsertLocal(
                                        BalanceHistoryLocal(
                                          id: historyId,
                                          parentId: clientId,
                                          parentType: 'client',
                                          enteredBalance: amount,
                                          balanceBefore: latestBalance,
                                          type: isAddition
                                              ? 'addition'
                                              : 'deduction',
                                          notes: noteStr,
                                          timestamp: selectedDate,
                                        ),
                                      );

                                      // ── Update cash box locally ──
                                      await BoxRepository.instance.increment(
                                          isAddition ? -amount : amount);

                                      // ── Enqueue balance sync to Firestore ──
                                      final logEntry = <String, dynamic>{
                                        'enteredBalance': amount,
                                        'balanceBefore': latestBalance,
                                        'type': isAddition
                                            ? 'addition'
                                            : 'deduction',
                                        'notes': noteStr,
                                        'timestamp':
                                            selectedDate.toIso8601String(),
                                      };
                                      await SyncQueueManager.instance.enqueue(
                                        operationType: 'adjustClientBalance',
                                        payload: {
                                          'clientId': clientId,
                                          'amount': amount,
                                          'isAddition': isAddition,
                                          'logEntry': logEntry,
                                          'newBalance': newBalance,
                                          'historyId': historyId,
                                        },
                                      );

                                      // ── Background: trigger sync + write voucher (fire-and-forget) ──
                                      if (isOnline) {
                                        ConnectivityService.instance.forceSync();
                                        FirebaseFirestore.instance
                                            .collection('client_vouchers')
                                            .add({
                                          'clientId': clientId,
                                          'clientName': clientName,
                                          'voucherNumber': vNumber,
                                          'direction': direction,
                                          'amount': amount,
                                          'description': descCtrl.text,
                                          'date': selectedDate,
                                          'paymentMethod': paymentMethod,
                                          'timestamp':
                                              FieldValue.serverTimestamp(),
                                        }).catchError((_) {});
                                      }

                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'تم إضافة المبلغ بنجاح')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'حدث خطأ أثناء الإضافة: $e')),
                                        );
                                      }
                                    } finally {
                                      if (ctx.mounted) {
                                        setDlg(() => isSaving = false);
                                      }
                                    }
                                  },
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.pink),
                                    ),
                                  )
                                : const Text('اضافة المبلغ',
                                    style: TextStyle(
                                        color: Colors.pink, fontSize: 15)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'الأرصدة الافتتاحية والمبالغ النقدية للعملاء',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black),
                      onPressed: _generating ? null : _showReportChoiceDialog,
                      child: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تقرير'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        hintText: 'بحث',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                      child: Text('عليه',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text('له',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('بيانات العميل',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('clients')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || _deletedClientsBox == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final clients = snapshot.data!.docs.where((d) {
                    if (_deletedClientsBox!.containsKey(d.id)) return false;
                    if (_search.isEmpty) return true;
                    final dData = d.data() as Map<String, dynamic>?;
                    return (dData?['clientName'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_search.toLowerCase());
                  }).toList();

                  return ListView.separated(
                    itemCount: clients.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = clients[index];
                      final docData = doc.data() as Map<String, dynamic>?;
                      final name = (docData?['clientName'] ?? '').toString();
                      double balance = (docData?['balance'] ?? 0.0).toDouble();
                      if (balance == 0.0) {
                        final local = ClientRepository.instance.getById(doc.id);
                        if (local != null && local.balance != 0.0) {
                          balance = local.balance;
                        }
                      }
                      final lahu = balance < 0 ? balance.abs() : 0.0;
                      final alayhi = balance > 0 ? balance : 0.0;

                      return InkWell(
                        onTap: () => _showAddAmountDialog(
                            context, doc.id, name, balance),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  color: Colors.grey.shade200,
                                  child: Text(
                                    alayhi.toStringAsFixed(2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  color: Colors.brown.shade100,
                                  child: Text(
                                    lahu.toStringAsFixed(2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(name,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Deferred Page ───────────────────────────────────────────────────────────

class _ClientDeferredPage extends StatefulWidget {
  const _ClientDeferredPage();

  @override
  State<_ClientDeferredPage> createState() => _ClientDeferredPageState();
}

class _ClientDeferredPageState extends State<_ClientDeferredPage> {
  String _search = '';
  bool _generating = false;

  void _showReportChoiceDialog(
      List<MapEntry<String, double>> allEntries, double grandTotal) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'اختر نوع التقرير',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.orange),
                title: const Text('تقرير المبالغ المتبقية من الفواتير الآجل'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf(allEntries, grandTotal);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('تقرير سند الصرف'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('عليه', 'تقرير سند الصرف');
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.green),
                title: const Text('تقرير سند القبض'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateVoucherPdf('له', 'تقرير سند القبض');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateVoucherPdf(String direction, String reportTitle) async {
    final voucherCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(reportTitle),
          content: TextField(
            controller: voucherCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رقم السند',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || voucherCtrl.text.trim().isEmpty) return;
    final voucherNumber = int.tryParse(voucherCtrl.text.trim());
    if (voucherNumber == null) return;

    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      final snap = await FirebaseFirestore.instance
          .collection('client_vouchers')
          .where('direction', isEqualTo: direction)
          .where('voucherNumber', isEqualTo: voucherNumber)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('لم يتم العثور على سند برقم $voucherNumber')),
          );
        }
        return;
      }

      final data = snap.docs.first.data();
      final voucherDate = (data['date'] is Timestamp)
          ? DateFormat('yyyy/MM/dd')
              .format((data['date'] as Timestamp).toDate())
          : data['date']?.toString() ?? '';
      final clientName = (data['clientName'] ?? '').toString();
      final amount = (data['amount'] ?? 0.0).toDouble();
      final description = (data['description'] ?? '').toString();
      final vNum = data['voucherNumber']?.toString() ?? '';

      pw.TextStyle s(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 11}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.TableRow row3(String arabic, String english, String value) =>
          pw.TableRow(
            children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(english, style: s()),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(value,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                    style: s(bold: true)),
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: pw.Text(arabic,
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.right,
                    style: s(bold: true)),
              ),
            ],
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: s(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: s(fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('#$vNum#', style: s(fontSize: 12)),
                    pw.Text(reportTitle,
                        textDirection: pw.TextDirection.rtl,
                        style: s(bold: true, fontSize: 16)),
                    pw.Text('ج.م', style: s(fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    row3('رقم السند', 'No.', vNum),
                    row3('التاريخ', 'Date', voucherDate),
                    row3('تم تسليم السيد/الساده', 'Pay To Mr/Mrs', clientName),
                    row3('مبلغ وقدره', 'Amount',
                        'فقط ${amount.toStringAsFixed(2)} ج.م لا غير'),
                    row3('وذلك مقابل', 'For', description),
                  ],
                ),
                pw.SizedBox(height: 60),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المدير',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('المستلم',
                            textDirection: pw.TextDirection.rtl,
                            style: s(bold: true)),
                        pw.SizedBox(height: 30),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeTitle = direction == 'عليه' ? 'sarf' : 'qabdh';
      final file = File(
          '${dir.path}/client_voucher_${safeTitle}_${vNum}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Text(reportTitle),
              content: const Text('تم إنشاء السند. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles([XFile(file.path)],
                        text: reportTitle);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء السند: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePdf(
      List<MapEntry<String, double>> entries, double grandTotal) async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(bold: true, fontSize: 9)),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(
                    bold: bold, color: red ? PdfColors.red : PdfColors.black)),
          );

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'ذمم العملاء - المبالغ المتبقية من الفواتير الآجل',
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('#'),
                        headerCell('اسم العميل'),
                        headerCell('المبلغ المتبقي'),
                      ],
                    ),
                    for (int i = 0; i < entries.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isEven ? PdfColors.white : PdfColors.grey50,
                        ),
                        children: [
                          dataCell('${i + 1}'),
                          dataCell(entries[i].key),
                          dataCell(entries[i].value.toStringAsFixed(2),
                              red: true),
                        ],
                      ),
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        dataCell(''),
                        dataCell('الإجمالي', bold: true, red: true),
                        dataCell(grandTotal.toStringAsFixed(2),
                            bold: true, red: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/client_deferred_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تقرير المبالغ المتبقية من الفواتير الآجل'),
              content: const Text('تم إنشاء التقرير. ماذا تريد أن تفعل؟'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Share.shareXFiles([XFile(file.path)],
                        text:
                            'ذمم العملاء - المبالغ المتبقية من الفواتير الآجل');
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await OpenFilex.open(file.path);
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'ذمم العملاء - الفواتير الآجل',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clients')
              .where('balance', isGreaterThan: 0)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text('لا توجد ذمم متبقية للعملاء'));
            }

            final allEntries = docs
                .map<MapEntry<String, double>>((d) {
                  final dData = d.data() as Map<String, dynamic>?;
                  return MapEntry(
                    (dData?['clientName'] ?? '').toString(),
                    ((dData?['balance'] ?? 0.0) as num).toDouble(),
                  );
                })
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final double grandTotal =
                allEntries.fold(0.0, (s, e) => s + e.value);
            final clientDocs = {
              for (final d in docs)
                ((d.data() as Map<String, dynamic>?)?['clientName'] ?? '').toString(): d
            };

            final filtered = _search.isEmpty
                ? allEntries
                : allEntries
                    .where((e) =>
                        e.key.toLowerCase().contains(_search.toLowerCase()))
                    .toList();

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              foregroundColor: Colors.black),
                          onPressed: _generating
                              ? null
                              : () => _showReportChoiceDialog(
                                  allEntries, grandTotal),
                          icon: _generating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf, size: 18),
                          label: const Text('تقرير'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            hintText: 'بحث',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.orange.shade100,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(grandTotal.toStringAsFixed(2),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.red)),
                      const Text('الإجمالي',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = filtered[index];
                      final doc = clientDocs[e.key];
                      final id = doc?.id ?? '';
                      return ListTile(
                        onTap: () => id.isNotEmpty
                            ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ClientInvoicesPage(clientId: id),
                                ))
                            : null,
                        title: Text(e.key,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const FaIcon(
                                FontAwesomeIcons.whatsapp,
                                color: Colors.green,
                                size: 22,
                              ),
                              onPressed: () async {
                                final docData =
                                    doc?.data() as Map<String, dynamic>?;
                                final rawPhone = docData != null
                                    ? (docData['phone'] ??
                                            docData['clientPhone'] ??
                                            docData['whatsapp'])
                                        ?.toString()
                                    : null;
                                final cleanPhone = (rawPhone != null &&
                                        rawPhone.trim().isNotEmpty)
                                    ? EgyptPhoneField.toWhatsappDigits(rawPhone)
                                    : null;

                                final balanceText = e.value > 0
                                    ? 'المتبقي عليكم للحساب هو: ${e.value.toStringAsFixed(2)} ج.م'
                                    : 'رصيدكم الدائن لدينا هو: ${e.value.abs().toStringAsFixed(2)} ج.م';

                                final message =
                                    'السلام عليكم ورحمة الله وبركاته،\n'
                                    'أ/ ${e.key}\n'
                                    'نود تذكيركم بأن $balanceText.\n'
                                    'نشكركم لتعاملكم معنا.';

                                final ok = await WhatsappInvoiceShareService
                                    .openWhatsappChat(
                                  phoneDigits: cleanPhone,
                                  message: message,
                                );
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'تعذر فتح واتساب. تأكد من تثبيت التطبيق أو صحة الرقم'),
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              e.value.toStringAsFixed(2),
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                        leading: const Icon(Icons.arrow_back_ios,
                            size: 16, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Remaining Report Page ───────────────────────────────────────────────────

class _ClientRemainingReportPage extends StatefulWidget {
  const _ClientRemainingReportPage();

  @override
  State<_ClientRemainingReportPage> createState() =>
      _ClientRemainingReportPageState();
}

class _ClientRemainingReportPageState
    extends State<_ClientRemainingReportPage> {
  bool _generating = false;

  Future<void> _generatePdf(List<QueryDocumentSnapshot> clients) async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 10}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget headerCell(String text) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(bold: true, fontSize: 9)),
          );

      pw.Widget dataCell(String text, {bool red = false, bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(text,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: cell(
                    bold: bold, color: red ? PdfColors.red : PdfColors.black)),
          );

      final grandTotal = clients.fold<double>(
          0.0, (s, d) {
            final dData = d.data() as Map<String, dynamic>?;
            return s + (dData?['balance'] ?? 0.0).toDouble();
          });

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'تقرير بالمتبقي للعملاء',
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 14),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        headerCell('#'),
                        headerCell('اسم العميل'),
                        headerCell('الإجمالي'),
                      ],
                    ),
                    for (int i = 0; i < clients.length; i++)
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: i.isEven ? PdfColors.white : PdfColors.grey50,
                        ),
                        children: [
                          dataCell('${i + 1}'),
                          dataCell(((clients[i].data() as Map<String, dynamic>?)?['clientName'] ?? '').toString()),
                          dataCell(
                              ((clients[i].data() as Map<String, dynamic>?)?['balance'] ?? 0.0)
                                  .toDouble()
                                  .toStringAsFixed(2),
                              red: true),
                        ],
                      ),
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        dataCell(''),
                        dataCell('الإجمالي', bold: true, red: true),
                        dataCell(grandTotal.toStringAsFixed(2),
                            bold: true, red: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/client_remaining_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)],
          text: 'تقرير المبالغ المتبقية للعملاء');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateSingleClientPdf(QueryDocumentSnapshot client) async {
    setState(() => _generating = true);
    try {
      final amiriRegularData = await rootBundle.load('fonts/Amiri-Regular.ttf');
      final amiriBoldData = await rootBundle.load('fonts/Amiri-Bold.ttf');
      final amiriRegular = pw.Font.ttf(amiriRegularData.buffer.asByteData());
      final amiriBold = pw.Font.ttf(amiriBoldData.buffer.asByteData());

      final now = DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy').format(now);
      final timeStr = DateFormat('hh:mm:ss a').format(now);

      pw.TextStyle cell(
              {bool bold = false,
              PdfColor color = PdfColors.black,
              double fontSize = 11}) =>
          pw.TextStyle(
            font: bold ? amiriBold : amiriRegular,
            fontSize: fontSize,
            color: color,
          );

      pw.Widget dataRow(String label, String value,
              {bool isRed = false, bool isBold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(value,
                    textDirection: pw.TextDirection.rtl,
                    style: cell(
                        bold: isBold,
                        color: isRed ? PdfColors.red : PdfColors.black,
                        fontSize: 12)),
                pw.Text(label,
                    textDirection: pw.TextDirection.rtl,
                    style: cell(bold: true, fontSize: 12)),
              ],
            ),
          );

      final clientData = client.data() as Map<String, dynamic>?;
      final clientName = (clientData?['clientName'] ?? '').toString();
      final balance = (clientData?['balance'] ?? 0.0).toDouble();
      final phone = (clientData != null && clientData.containsKey('phone'))
          ? (clientData['phone'] ?? '').toString()
          : '';

      String balanceStatus = 'خالص';
      double displayBalance = balance;
      bool isRed = false;
      if (balance > 0) {
        balanceStatus = 'عليه (مدين)';
        isRed = true;
      } else if (balance < 0) {
        balanceStatus = 'له (دائن)';
        displayBalance = balance.abs();
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date: $dateStr', style: cell(fontSize: 9)),
                        pw.Text('Time: $timeStr', style: cell(fontSize: 9)),
                      ],
                    ),
                    pw.Text(
                      'كشف حساب عميل',
                      textDirection: pw.TextDirection.rtl,
                      style: cell(bold: true, fontSize: 16),
                    ),
                    pw.SizedBox(width: 50),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 20),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  padding: const pw.EdgeInsets.all(16),
                  child: pw.Column(
                    children: [
                      dataRow('اسم العميل:', clientName, isBold: true),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey200),
                      dataRow('رقم الهاتف (واتساب):',
                          phone.isNotEmpty ? phone : 'غير متوفر'),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey200),
                      dataRow('حالة الحساب:', balanceStatus,
                          isRed: isRed, isBold: true),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey200),
                      dataRow('المبلغ المتبقي:',
                          '${displayBalance.toStringAsFixed(2)} ج.م',
                          isRed: isRed, isBold: true),
                    ],
                  ),
                ),
                pw.SizedBox(height: 50),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('توقيع المستلم',
                            textDirection: pw.TextDirection.rtl,
                            style: cell(bold: true)),
                        pw.SizedBox(height: 40),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('توقيع المدير',
                            textDirection: pw.TextDirection.rtl,
                            style: cell(bold: true)),
                        pw.SizedBox(height: 40),
                        pw.Container(
                            width: 120, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/client_statement_${clientName}_${dateStr.replaceAll('/', '-')}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)],
          text: 'كشف حساب العميل $clientName');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _onPdfReportPressed(List<QueryDocumentSnapshot> clients) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تصدير تقرير PDF',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: const Text('كشف حساب لعميل محدد'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final selectedClient =
                      await showDialog<QueryDocumentSnapshot>(
                    context: context,
                    builder: (context) =>
                        _ClientSelectionDialog(clients: clients),
                  );
                  if (selectedClient != null) {
                    _generateSingleClientPdf(selectedClient);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.people, color: Colors.green),
                title: const Text('تقرير بجميع العملاء (ذمم العملاء)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdf(clients);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'ذمم العملاء - تقرير',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('clients').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final clients = snapshot.data!.docs
                .where((d) {
                  final dData = d.data() as Map<String, dynamic>?;
                  return (dData?['balance'] ?? 0.0) != 0.0;
                })
                .toList()
              ..sort((a, b) {
                final aData = a.data() as Map<String, dynamic>?;
                final bData = b.data() as Map<String, dynamic>?;
                final aBalance = (aData?['balance'] ?? 0.0) as num;
                final bBalance = (bData?['balance'] ?? 0.0) as num;
                return bBalance.compareTo(aBalance);
              });

            if (clients.isEmpty) {
              return const Center(child: Text('لا توجد أرصدة متبقية للعملاء'));
            }

            final grandTotal = clients.fold<double>(
                0.0, (s, d) {
                  final dData = d.data() as Map<String, dynamic>?;
                  return s + (dData?['balance'] ?? 0.0).toDouble();
                });

            return Stack(
              children: [
                Column(
                  children: [
                    Container(
                      color: Colors.orange.shade100,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(grandTotal.toStringAsFixed(2),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.red)),
                          const Text('الإجمالي',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: clients.length,
                        itemBuilder: (context, index) {
                          final doc = clients[index];
                          final docData = doc.data() as Map<String, dynamic>?;
                          final balance = (docData?['balance'] ?? 0.0).toDouble();
                          return ListTile(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ClientInvoicesPage(clientId: doc.id),
                              ),
                            ),
                            title: Text(((doc.data() as Map<String, dynamic>?)?['clientName'] ?? '').toString(),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const FaIcon(
                                    FontAwesomeIcons.whatsapp,
                                    color: Colors.green,
                                    size: 22,
                                  ),
                                  onPressed: () async {
                                    final docData =
                                        doc.data() as Map<String, dynamic>?;
                                    final rawPhone = docData != null
                                        ? (docData['phone'] ??
                                                docData['clientPhone'] ??
                                                docData['whatsapp'])
                                            ?.toString()
                                        : null;
                                    final cleanPhone = (rawPhone != null &&
                                            rawPhone.trim().isNotEmpty)
                                        ? EgyptPhoneField.toWhatsappDigits(
                                            rawPhone)
                                        : null;

                                    final balanceText = balance > 0
                                        ? 'المتبقي عليكم للحساب هو: ${balance.toStringAsFixed(2)} ج.م'
                                        : 'رصيدكم الدائن لدينا هو: ${balance.abs().toStringAsFixed(2)} ج.م';

                                    final message =
                                        'السلام عليكم ورحمة الله وبركاته،\n'
                                        'أ/ ${((doc.data() as Map<String, dynamic>?)?['clientName'] ?? '').toString()}\n'
                                        'نود تذكيركم بأن $balanceText.\n'
                                        'نشكركم لتعاملكم معنا.';

                                    final ok = await WhatsappInvoiceShareService
                                        .openWhatsappChat(
                                      phoneDigits: cleanPhone,
                                      message: message,
                                    );
                                    if (!ok && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'تعذر فتح واتساب. تأكد من تثبيت التطبيق أو صحة الرقم'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  balance.toStringAsFixed(2),
                                  style: TextStyle(
                                    color:
                                        balance > 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (_generating)
                  Container(
                    color: Colors.black38,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        ),
        floatingActionButton: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('clients').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            final clients = snapshot.data!.docs
                .where((d) {
                  final dData = d.data() as Map<String, dynamic>?;
                  return (dData?['balance'] ?? 0.0) != 0.0;
                })
                .toList();
            return FloatingActionButton.extended(
              backgroundColor: Colors.black87,
              onPressed:
                  _generating ? null : () => _onPdfReportPressed(clients),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('تقرير PDF',
                  style: TextStyle(color: Colors.white)),
            );
          },
        ),
      ),
    );
  }
}

// ─── Balance Report Page ─────────────────────────────────────────────────────

class _ClientBalanceReportPage extends StatefulWidget {
  const _ClientBalanceReportPage();

  @override
  State<_ClientBalanceReportPage> createState() =>
      _ClientBalanceReportPageState();
}

class _ClientBalanceReportPageState extends State<_ClientBalanceReportPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'العملاء المتبقي لهم أرصدة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clients')
              .where('balance', isLessThan: 0)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final clients = snapshot.data!.docs;
            if (clients.isEmpty) {
              return const Center(child: Text('لا يوجد عملاء لديهم أرصدة'));
            }

            final filtered = _search.isEmpty
                ? clients
                : clients
                    .where((d) {
                      final dData = d.data() as Map<String, dynamic>?;
                      return (dData?['clientName'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_search.toLowerCase());
                    })
                    .toList();

            final grandTotal = clients.fold<double>(
                0.0, (s, d) {
                  final dData = d.data() as Map<String, dynamic>?;
                  return s + (dData?['balance'] ?? 0.0).toDouble().abs();
                });

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن عميل',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                Container(
                  color: Colors.orange.shade100,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(grandTotal.toStringAsFixed(2),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green)),
                      const Text('الإجمالي',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('لا توجد نتائج مطابقة للبحث'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            final docData = doc.data() as Map<String, dynamic>?;
                            final balance = (docData?['balance'] ?? 0.0).toDouble();
                            return ListTile(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ClientInvoicesPage(clientId: doc.id),
                                ),
                              ),
                              title: Text(((doc.data() as Map<String, dynamic>?)?['clientName'] ?? '').toString(),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              trailing: Text(
                                balance.abs().toStringAsFixed(2),
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Balance Check Page ──────────────────────────────────────────────────────

class _ClientBalanceCheckPage extends StatefulWidget {
  const _ClientBalanceCheckPage();

  @override
  State<_ClientBalanceCheckPage> createState() =>
      _ClientBalanceCheckPageState();
}

class _ClientBalanceCheckPageState extends State<_ClientBalanceCheckPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'فحص ارصدة العملاء',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'ابحث عن عميل',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('clients')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data!.docs.where((d) {
                    if (_search.isEmpty) return true;
                    final dData = d.data() as Map<String, dynamic>?;
                    return (dData?['clientName'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_search.toLowerCase());
                  }).toList();

                  return ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final doc = all[index];
                      final docData = doc.data() as Map<String, dynamic>?;
                      final balance = (docData?['balance'] ?? 0.0).toDouble();
                      return ListTile(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ClientInvoicesPage(clientId: doc.id),
                          ),
                        ),
                        title: Text(((doc.data() as Map<String, dynamic>?)?['clientName'] ?? '').toString(),
                            textAlign: TextAlign.right,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text(
                          balance.toStringAsFixed(2),
                          style: TextStyle(
                            color: balance > 0
                                ? Colors.red
                                : balance < 0
                                    ? Colors.orange
                                    : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Client List Page (عرض العملاء) ─────────────────────────────────────────

class _ClientListPage extends StatefulWidget {
  const _ClientListPage();

  @override
  State<_ClientListPage> createState() => _ClientListPageState();
}

class _ClientListPageState extends State<_ClientListPage> {
  String _searchQuery = '';
  Box<String>? _deletedClientsBox;
  List<Map<String, dynamic>> _clients = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _initializeHive();
    _loadFromHive();
    _backgroundSync();
  }

  Future<void> _initializeHive() async {
    final box = Hive.isBoxOpen('deletedClients')
        ? Hive.box<String>('deletedClients')
        : await Hive.openBox<String>('deletedClients');
    if (mounted) {
      setState(() {
        _deletedClientsBox = box;
      });
    }
  }

  /// Load clients instantly from Hive (0ms)
  void _loadFromHive() {
    final locals = ClientRepository.instance.getAll();
    if (mounted) {
      setState(() {
        _clients = locals
            .map((c) => <String, dynamic>{
                  'id': c.id,
                  'clientName': c.name,
                  'balance': BalanceHistoryRepository.instance
                      .calculateClientBalance(c.id, fallback: c.balance),
                  'phone': c.phone,
                })
            .toList();
      });
    }
  }

  /// Background sync from Firestore → Hive, then refresh display
  Future<void> _backgroundSync() async {
    if (!ConnectivityService.instance.isOnline) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      await ClientRepository.instance.deltaSync();
      _loadFromHive(); // refresh from freshly synced Hive
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showDeleteConfirmationDialog(String clientId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content:
            const Text('هل تريد حذف هذا العميل نهائياً من قاعدة البيانات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                if (_deletedClientsBox != null &&
                    _deletedClientsBox!.containsKey(clientId)) {
                  await _deletedClientsBox!.delete(clientId);
                }
                // 1. Delete from local Hive immediately
                await ClientRepository.instance.deleteLocal(clientId);
                await BalanceHistoryRepository.instance
                    .deleteForParent('client', clientId);
                _loadFromHive();

                // 2. Delete from Firestore
                await FirebaseFirestore.instance
                    .collection('clients')
                    .doc(clientId)
                    .delete()
                    .catchError((e) {
                  debugPrint('Firestore client delete error: $e');
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف العميل بنجاح')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ أثناء الحذف: $e')),
                  );
                }
              }
            },
            child: const Text('نعم'),
          ),
        ],
      ),
    );
  }

  void _showClientOptionsSheet(
    String clientId,
    String currentName,
    String currentPhone,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تغيير الاسم'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showRenameClientDialog(clientId, currentName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('تغيير رقم الهاتف'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditClientPhoneDialog(clientId, currentPhone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف من القائمة'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDeleteConfirmationDialog(clientId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditClientPhoneDialog(String clientId, String currentPhone) {
    final controller = TextEditingController(
      text: EgyptPhoneField.toLocalPartForInput(currentPhone),
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير رقم الهاتف'),
        content: EgyptPhoneField(
          controller: controller,
          labelText: 'رقم الهاتف (واتساب)',
          hintText: '1xxxxxxxxx (اتركه فارغاً للحذف)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              final phoneLocal = controller.text.trim();
              if (phoneLocal.isNotEmpty &&
                  !EgyptPhoneField.isValidLocalPart(phoneLocal)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'رقم الهاتف غير صحيح. اتركه فارغاً أو أدخل رقماً صالحاً',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              _performClientPhoneUpdate(clientId, phoneLocal, currentPhone);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _performClientPhoneUpdate(
    String clientId,
    String phoneLocal,
    String previousPhone,
  ) async {
    final newDigits =
        phoneLocal.isEmpty ? '' : EgyptPhoneField.toWhatsappDigits(phoneLocal);
    final oldDigits = previousPhone.replaceAll(RegExp(r'\D'), '');
    if (newDigits == oldDigits) return;

    // Update Hive immediately
    final local = ClientRepository.instance.getById(clientId);
    if (local != null) {
      final data = <String, dynamic>{
        'clientName': local.name,
        'balance': local.balance,
        'id': clientId,
        'phone': newDigits.isEmpty ? null : newDigits,
      };
      await ClientRepository.instance.upsertLocal(clientId, data);
      _loadFromHive();
    }

    // Background sync to Firestore
    if (newDigits.isEmpty) {
      FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .update({'phone': FieldValue.delete()}).catchError((_) {});
    } else {
      FirebaseFirestore.instance
          .collection('clients')
          .doc(clientId)
          .update({'phone': newDigits}).catchError((_) {});
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newDigits.isEmpty
                ? 'تم حذف رقم الهاتف'
                : 'تم تحديث رقم الهاتف بنجاح',
          ),
        ),
      );
    }
  }

  void _showRenameClientDialog(String clientId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير اسم العميل'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'الاسم الجديد',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(dialogContext);
              if (newName.isEmpty || newName == currentName) return;
              _performClientRename(clientId, newName);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _performClientRename(String clientId, String newName) async {
    // Use PartyRenameService which already handles Hive + Firestore
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          color: Colors.orange.withOpacity(0.7),
        ),
      ),
    );
    try {
      await PartyRenameService.renameClient(
        oldClientId: clientId,
        newName: newName,
      );
      _loadFromHive();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الاسم بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletedIds = _deletedClientsBox?.keys.cast<String>().toSet() ?? {};
    final visible = _clients.where((c) {
      final id = c['id']?.toString() ?? '';
      if (deletedIds.contains(id)) return false;
      if (_searchQuery.isEmpty) return true;
      final name = (c['clientName'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _backgroundSync,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _deletedClientsBox == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeletedClientsPage(
                          deletedClients:
                              _deletedClientsBox!.values.toSet(),
                          onRestoreClient: (clientId) {
                            _deletedClientsBox!.delete(clientId);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
          ),
        ],
        backgroundColor: Colors.black.withOpacity(0.7),
        title: const Text(
          'عرض العملاء',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: TextField(
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.black.withOpacity(0.7)),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
                labelText: 'ابحث عن عميل',
                labelStyle: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 18,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('لا يوجد عملاء', style: TextStyle(fontSize: 16)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppResponsive.gridColumns(context),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final c = visible[index];
                      final id = c['id']?.toString() ?? '';
                      final name = (c['clientName'] ?? '').toString();
                      final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
                      final phone = (c['phone'] ?? '').toString();

                      return _PartyInfoCard(
                        name: name,
                        balance: balance,
                        phone: phone,
                        isClient: true,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ClientInvoicesPage(clientId: id),
                            ),
                          );
                          _loadFromHive();
                        },
                        onLongPress: () {
                          _showClientOptionsSheet(id, name, phone);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}


class _ClientSelectionDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> clients;
  const _ClientSelectionDialog({Key? key, required this.clients})
      : super(key: key);

  @override
  State<_ClientSelectionDialog> createState() => _ClientSelectionDialogState();
}

class _ClientSelectionDialogState extends State<_ClientSelectionDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.clients.where((c) {
      final cData = c.data() as Map<String, dynamic>?;
      final name = (cData?['clientName'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختر عميل لتصدير التقرير'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'بحث عن عميل...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('لا يوجد نتائج'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final docData = doc.data() as Map<String, dynamic>?;
                          final name = (docData?['clientName'] ?? '').toString();
                          final balance = (docData?['balance'] ?? 0.0).toDouble();
                          return ListTile(
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle:
                                Text('الرصيد: ${balance.toStringAsFixed(2)}'),
                            onTap: () => Navigator.pop(context, doc),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
