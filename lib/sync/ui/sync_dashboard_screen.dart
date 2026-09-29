import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../../local_db/hive_init.dart';
import '../../local_db/models/sync_queue_item.dart';
import '../../repositories/data_sync_service.dart';
import '../../sync/batch_sync_engine.dart';
import '../../sync/connectivity_service.dart';
import '../../sync/sync_queue_manager.dart';
import '../../sync/sync_operation_diagnostics.dart';
import '../../sync/sync_operation_inspector.dart';

/// Sync Dashboard Screen — visible to all users.
///
/// Shows:
///  - Current online/offline status
///  - List of pending, syncing, and failed operations
///  - "Sync Now" manual trigger button
///  - Last successful sync timestamp
///  - Failed item error details
class SyncDashboardScreen extends StatefulWidget {
  const SyncDashboardScreen({super.key});

  @override
  State<SyncDashboardScreen> createState() => _SyncDashboardScreenState();
}

class _SyncDashboardScreenState extends State<SyncDashboardScreen> {
  bool _isSyncing = false;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub = ConnectivityService.instance.onlineStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (ConnectivityService.instance.isOnline) {
      await DataSyncService.instance
          .syncOnStartup(includeRealtimeCollections: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _forceSync() async {
    setState(() => _isSyncing = true);
    try {
      await ConnectivityService.instance.forceSync();
      await DataSyncService.instance
          .syncOnStartup(includeRealtimeCollections: false);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  String _cloudRefreshMessage(Object? error) {
    final lower = error?.toString().toLowerCase() ?? '';
    if (lower.contains('resource-exhausted') ||
        lower.contains('resource exhausted')) {
      return 'توقّف التحديث السحابي لأن حصة Firebase المتاحة قد نفدت. '
          'البيانات المحلية محفوظة؛ انتظر تجدد الحصة أو راجع خطة Firebase.';
    }
    return 'تعذر تحديث البيانات السحابية مؤقتاً. يمكنك متابعة العمل من البيانات المحلية.';
  }

  Future<void> _retryItem(SyncQueueItem item) async {
    final started =
        await ConnectivityService.instance.retryOperation(item.operationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(started
          ? 'تم بدء إعادة محاولة هذه العملية'
          : 'هذه العملية تحتاج مراجعة سبب الخطأ قبل إعادة المحاولة'),
    ));
    setState(() {});
  }

  String _diagnosticText(SyncQueueItem item) {
    final info = SyncOperationDiagnostics.fromItem(item);
    return [
      'Operation ID: ${item.operationId}',
      'Type: ${item.operationType}',
      if (info.invoiceNumber != null) 'Invoice number: ${info.invoiceNumber}',
      if (info.invoiceId != null) 'Invoice ID: ${info.invoiceId}',
      if (info.partyName != null) 'Party: ${info.partyName}',
      if (info.partyId != null) 'Party ID: ${info.partyId}',
      if (info.amount != null) 'Amount: ${info.amount}',
      'Created: ${item.createdAt.toIso8601String()}',
      'Attempts: ${item.retryCount}',
      if (item.lastAttemptAt != null)
        'Last attempt: ${item.lastAttemptAt!.toIso8601String()}',
      if (item.errorCategory != null) 'Category: ${item.errorCategory}',
      if (item.errorCode != null) 'Code: ${item.errorCode}',
      if (item.lastError != null) 'Error: ${item.lastError}',
    ].join('\n');
  }

  bool _hasSafeFinancialPayload(SyncQueueItem item) {
    try {
      return SyncQueueManager.decodePayload(item)['financialFormat'] == 2;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showDetails(SyncQueueItem item) async {
    final info = SyncOperationDiagnostics.fromItem(item);
    List<dynamic> attempts = const [];
    try {
      attempts = jsonDecode(item.attemptHistoryJson) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff16213e),
        title: const Text('تفاصيل عملية المزامنة',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              _operationLabel(item.operationType),
              if (info.invoiceNumber != null)
                'رقم الفاتورة: ${info.invoiceNumber}',
              if (info.invoiceId != null) 'معرف الفاتورة: ${info.invoiceId}',
              if (info.partyName != null)
                '${info.partyType == 'supplier' ? 'المورد' : 'العميل'}: ${info.partyName}',
              if (info.partyId != null) 'معرف الطرف: ${info.partyId}',
              if (info.amount != null)
                'القيمة: ${intl.NumberFormat.decimalPattern().format(info.amount)}',
              'معرف العملية: ${item.operationId}',
              'تاريخ الحفظ: ${item.createdAt.toLocal()}',
              'عدد المحاولات: ${item.retryCount}',
              if (item.lastAttemptAt != null)
                'آخر محاولة: ${item.lastAttemptAt!.toLocal()}',
              if (item.nextRetryAt != null)
                'المحاولة التالية: ${item.nextRetryAt!.toLocal()}',
              if (item.errorCategory != null)
                'تصنيف الخطأ: ${item.errorCategory}',
              if (item.errorCode != null) 'رمز الخطأ: ${item.errorCode}',
              if (item.lastError != null) 'الخطأ التقني: ${item.lastError}',
              'سجل المحاولات المحفوظ: ${attempts.length}',
            ].join('\n\n'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: _diagnosticText(item)));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('تم نسخ بيانات التشخيص')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ التشخيص'),
          ),
          if (_hasSafeFinancialPayload(item))
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showCloudComparison(item);
              },
              icon: const Icon(Icons.compare_arrows),
              label: const Text('مقارنة Firebase'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloudComparison(SyncQueueItem item) async {
    final future = SyncOperationInspector().inspect(item);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff16213e),
        title: const Text('مقارنة آمنة للقراءة فقط',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<SyncOperationInspection>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('تعذر قراءة Firebase: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent));
              }
              final result = snapshot.data!;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.receiptExists
                          ? 'يوجد إيصال سحابي: العملية طُبقت بنجاح.'
                          : 'لا يوجد إيصال سحابي لهذه العملية.',
                      style: TextStyle(
                        color: result.receiptExists
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...result.checks.map((check) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${check.action == 'delete' ? 'حذف' : 'كتابة'}: ${check.path}\n'
                            '${check.appliedBy(item.operationId) ? 'يحمل معرف هذه العملية' : check.exists ? 'موجود بمعرف آخر' : 'غير موجود'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  String _lastSyncTime(String key) {
    final val = appMetaBox.get(key) as String?;
    if (val == null) return 'لم تتم مزامنة بعد';
    try {
      final dt = DateTime.parse(val).toLocal();
      return intl.DateFormat('yyyy/MM/dd – hh:mm a').format(dt);
    } catch (_) {
      return val;
    }
  }

  String _operationLabel(String type) {
    const labels = {
      'createInvoice': 'إنشاء فاتورة مبيعات',
      'editInvoice': 'تعديل فاتورة',
      'updateInvoiceSpecial': 'تحديث تمييز فاتورة',
      'deleteInvoice': 'حذف فاتورة',
      'adjustClientBalance': 'تعديل رصيد عميل',
      'adjustSupplierBalance': 'تعديل رصيد مورد',
      'createProduct': 'إضافة منتج',
      'editProduct': 'تعديل منتج',
      'deleteProduct': 'حذف منتج',
      'createReturn': 'إنشاء مرتجع مبيعات',
      'deleteReturn': 'حذف مرتجع مبيعات',
      'deleteReturnInvoice': 'حذف مرتجع مبيعات',
      'createBuyingInvoice': 'إنشاء فاتورة مشتريات',
      'editBuyingInvoice': 'تعديل فاتورة مشتريات',
      'deleteBuyingInvoice': 'حذف فاتورة مشتريات',
      'createClient': 'إنشاء عميل',
      'createSupplier': 'إنشاء مورد',
      'updateBox': 'تعديل الصندوق',
    };
    return labels[type] ?? type;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'synced':
        return Colors.green;
      case 'syncing':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(SyncQueueItem item) {
    switch (item.status) {
      case 'synced':
        return 'تمت المزامنة';
      case 'syncing':
        return 'جارٍ الرفع...';
      case 'failed':
        if (item.errorCategory == SyncErrorCategories.quota ||
            item.errorCode == 'resource-exhausted') {
          return 'بانتظار تجدد حصة Firebase';
        }
        return SyncQueueManager.instance.canRetry(item)
            ? 'فشل مؤقت'
            : 'تحتاج مراجعة';
      default:
        return 'في انتظار الرفع';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'synced':
        return Icons.cloud_done;
      case 'syncing':
        return Icons.sync;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.schedule;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1a1a2e),
      appBar: AppBar(
        backgroundColor: const Color(0xff16213e),
        foregroundColor: Colors.white,
        title: Text(
          'لوحة المزامنة',
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _refresh,
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<SyncQueueItem>>(
        valueListenable: syncQueueBox.listenable(),
        builder: (context, box, _) {
          final isOnline = ConnectivityService.instance.isOnline;
          final pending = SyncQueueManager.instance.pendingCount;
          final totalCount = SyncQueueManager.instance.totalCount;
          final hasSyncing = SyncQueueManager.instance.hasSyncingItems;
          final isBatchRunning = BatchSyncEngine.instance.isRunning;
          final items = SyncQueueManager.instance.getAll();

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: Colors.orange,
            child: ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                ValueListenableBuilder(
                    valueListenable: appMetaBox.listenable(),
                    builder: (context, box, _) =>
                        box.get('cloudRefreshError') == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    _cloudRefreshMessage(
                                        box.get('cloudRefreshError')),
                                    style: const TextStyle(
                                        color: Colors.redAccent)))),
                // ── Status Card ────────────────────────────────────────────
                _StatusCard(
                  isOnline: isOnline,
                  pendingCount: pending,
                  totalCount: totalCount,
                  hasSyncingItems: hasSyncing,
                  isSyncing: _isSyncing || isBatchRunning,
                ),
                SizedBox(height: 16.h),

                // ── Sync Now Button ────────────────────────────────────────
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isSyncing || isBatchRunning)
                        ? Colors.grey.shade700
                        : Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  onPressed: (_isSyncing || isBatchRunning) ? null : _forceSync,
                  icon: (_isSyncing || isBatchRunning)
                      ? SizedBox(
                          width: 18.w,
                          height: 18.h,
                          child: const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    (_isSyncing || isBatchRunning)
                        ? 'جارٍ المزامنة...'
                        : 'مزامنة الآن',
                    style:
                        TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 20.h),

                // ── Last Sync Info ─────────────────────────────────────────
                const _SectionTitle(title: 'آخر مزامنة ناجحة'),
                SizedBox(height: 8.h),
                ValueListenableBuilder<Box>(
                  valueListenable: appMetaBox.listenable(),
                  builder: (context, metaBox, _) {
                    return Column(
                      children: [
                        _InfoRow(
                          icon: Icons.inventory_2_outlined,
                          label: 'المنتجات',
                          value: _lastSyncTime(HiveMetaKeys.lastProductSyncAt),
                        ),
                        _InfoRow(
                          icon: Icons.people_outline,
                          label: 'العملاء',
                          value: _lastSyncTime(HiveMetaKeys.lastClientSyncAt),
                        ),
                        _InfoRow(
                          icon: Icons.local_shipping_outlined,
                          label: 'الموردون',
                          value: _lastSyncTime(HiveMetaKeys.lastSupplierSyncAt),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 20.h),

                // ── Pending Queue ──────────────────────────────────────────
                _SectionTitle(
                  title: items.isEmpty
                      ? 'قائمة العمليات المعلقة'
                      : 'قائمة العمليات (${items.length})',
                ),
                SizedBox(height: 8.h),

                if (items.isEmpty)
                  _EmptyQueueCard()
                else
                  ...items.map((item) => _QueueItemCard(
                        item: item,
                        operationLabel: _operationLabel(item.operationType),
                        statusColor: _statusColor(item.status),
                        statusLabel: _statusLabel(item),
                        statusIcon: _statusIcon(item.status),
                        onRetry: () => _retryItem(item),
                        onDetails: () => _showDetails(item),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isOnline;
  final int pendingCount;
  final int totalCount;
  final bool hasSyncingItems;
  final bool isSyncing;

  const _StatusCard({
    required this.isOnline,
    required this.pendingCount,
    required this.totalCount,
    required this.hasSyncingItems,
    required this.isSyncing,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    IconData icon;
    String title;
    String subtitle;

    if (isSyncing || hasSyncingItems) {
      bg = Colors.blue.shade800;
      icon = Icons.sync;
      title = 'جارٍ المزامنة...';
      subtitle = 'يتم رفع البيانات إلى الخادم';
    } else if (!isOnline && totalCount > 0) {
      bg = Colors.orange.shade800;
      icon = Icons.cloud_off;
      title = 'غير متصل بالإنترنت';
      subtitle =
          '$totalCount عملية محفوظة محلياً — ستُرفع تلقائياً عند الاتصال';
    } else if (!isOnline) {
      bg = Colors.grey.shade800;
      icon = Icons.cloud_off_outlined;
      title = 'غير متصل بالإنترنت';
      subtitle = 'لا توجد عمليات معلقة — جميع البيانات محفوظة';
    } else if (totalCount > 0) {
      bg = Colors.amber.shade800;
      icon = Icons.schedule;
      title = 'في انتظار المزامنة';
      subtitle = '$totalCount عملية في القائمة بانتظار الرفع';
    } else {
      bg = Colors.green.shade800;
      icon = Icons.cloud_done;
      title = 'متصل بالإنترنت';
      subtitle = 'جميع البيانات مُزامنة مع الخادم ✓';
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
              color: bg.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 40.sp),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4.h),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.sp)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
          color: Colors.white70,
          fontSize: 13.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xff16213e),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 18.sp),
          SizedBox(width: 10.w),
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _EmptyQueueCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: const Color(0xff16213e),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 48.sp),
          SizedBox(height: 12.h),
          Text(
            'لا توجد عمليات معلقة',
            style: TextStyle(
                color: Colors.white,
                fontSize: 15.sp,
                fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6.h),
          Text(
            'جميع البيانات تمت مزامنتها بنجاح',
            style: TextStyle(color: Colors.white54, fontSize: 12.sp),
          ),
        ],
      ),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  final SyncQueueItem item;
  final String operationLabel;
  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;
  final Future<void> Function() onRetry;
  final Future<void> Function() onDetails;

  const _QueueItemCard({
    required this.item,
    required this.operationLabel,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.onRetry,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final date =
        intl.DateFormat('MM/dd hh:mm a').format(item.createdAt.toLocal());
    final diagnostics = SyncOperationDiagnostics.fromItem(item);
    final canRetry =
        item.status == 'failed' && SyncQueueManager.instance.canRetry(item);
    final failure = item.lastError == null
        ? null
        : SyncFailureClassifier.classify(item.lastError!);

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xff16213e),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  operationLabel,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 11.sp),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.white38, size: 13.sp),
              SizedBox(width: 4.w),
              Text(date,
                  style: TextStyle(color: Colors.white38, fontSize: 11.sp)),
              if (item.retryCount > 0) ...[
                SizedBox(width: 12.w),
                Icon(Icons.replay, color: Colors.orange, size: 13.sp),
                SizedBox(width: 4.w),
                Text('محاولة ${item.retryCount}',
                    style: TextStyle(color: Colors.orange, fontSize: 11.sp)),
              ],
            ],
          ),
          if (diagnostics.invoiceNumber != null ||
              diagnostics.partyName != null ||
              diagnostics.amount != null) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 12.w,
              runSpacing: 4.h,
              children: [
                if (diagnostics.invoiceNumber != null)
                  _DiagnosticChip(
                      icon: Icons.receipt_long,
                      text: 'فاتورة ${diagnostics.invoiceNumber}'),
                if (diagnostics.partyName != null)
                  _DiagnosticChip(
                      icon: diagnostics.partyType == 'supplier'
                          ? Icons.local_shipping_outlined
                          : Icons.person_outline,
                      text: diagnostics.partyName!),
                if (diagnostics.amount != null)
                  _DiagnosticChip(
                      icon: Icons.payments_outlined,
                      text: intl.NumberFormat.decimalPattern()
                          .format(diagnostics.amount)),
              ],
            ),
          ],
          if (item.lastError != null && item.lastError!.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (failure != null)
                    Text(failure.userMessageAr,
                        style: TextStyle(
                            color: Colors.red.shade200, fontSize: 11.sp)),
                  if (item.nextRetryAt != null) ...[
                    SizedBox(height: 4.h),
                    Text(
                      'المحاولة التلقائية التالية: ${intl.DateFormat('hh:mm:ss a').format(item.nextRetryAt!.toLocal())}',
                      style: TextStyle(
                          color: Colors.orange.shade200, fontSize: 10.sp),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline),
                label: const Text('التفاصيل'),
              ),
              if (canRetry)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay),
                  label: const Text('إعادة المحاولة'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DiagnosticChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );
}
