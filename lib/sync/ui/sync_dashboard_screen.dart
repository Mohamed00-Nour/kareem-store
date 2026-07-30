import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import '../../local_db/hive_init.dart';
import '../../local_db/models/sync_queue_item.dart';
import '../../sync/connectivity_service.dart';
import '../../sync/sync_queue_manager.dart';

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
  List<SyncQueueItem> _items = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _items = SyncQueueManager.instance.getAll();
    });
  }

  Future<void> _forceSync() async {
    setState(() => _isSyncing = true);
    try {
      await ConnectivityService.instance.forceSync();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _refresh();
      }
    }
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
      'deleteInvoice': 'حذف فاتورة',
      'adjustClientBalance': 'تعديل رصيد عميل',
      'adjustSupplierBalance': 'تعديل رصيد مورد',
      'createProduct': 'إضافة منتج',
      'editProduct': 'تعديل منتج',
      'deleteProduct': 'حذف منتج',
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

  String _statusLabel(String status) {
    switch (status) {
      case 'synced':
        return 'تمت المزامنة';
      case 'syncing':
        return 'جارٍ الرفع...';
      case 'failed':
        return 'فشلت المزامنة';
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
    final isOnline = ConnectivityService.instance.isOnline;
    final pending = SyncQueueManager.instance.pendingCount;

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
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        color: Colors.orange,
        child: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            // ── Status Card ────────────────────────────────────────────
            _StatusCard(
              isOnline: isOnline,
              pendingCount: pending,
              isSyncing: _isSyncing,
            ),
            SizedBox(height: 16.h),

            // ── Sync Now Button ────────────────────────────────────────
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSyncing
                    ? Colors.grey.shade700
                    : Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r)),
              ),
              onPressed: _isSyncing ? null : _forceSync,
              icon: _isSyncing
                  ? SizedBox(
                      width: 18.w,
                      height: 18.h,
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _isSyncing ? 'جارٍ المزامنة...' : 'مزامنة الآن',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20.h),

            // ── Last Sync Info ─────────────────────────────────────────
            const _SectionTitle(title: 'آخر مزامنة ناجحة'),
            SizedBox(height: 8.h),
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
            SizedBox(height: 20.h),

            // ── Pending Queue ──────────────────────────────────────────
            _SectionTitle(
              title: _items.isEmpty
                  ? 'قائمة العمليات المعلقة'
                  : 'قائمة العمليات (${_items.length})',
            ),
            SizedBox(height: 8.h),

            if (_items.isEmpty)
              _EmptyQueueCard()
            else
              ..._items.map((item) => _QueueItemCard(
                    item: item,
                    operationLabel: _operationLabel(item.operationType),
                    statusColor: _statusColor(item.status),
                    statusLabel: _statusLabel(item.status),
                    statusIcon: _statusIcon(item.status),
                  )),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isOnline;
  final int pendingCount;
  final bool isSyncing;

  const _StatusCard({
    required this.isOnline,
    required this.pendingCount,
    required this.isSyncing,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    IconData icon;
    String title;
    String subtitle;

    if (isSyncing) {
      bg = Colors.blue.shade800;
      icon = Icons.sync;
      title = 'جارٍ المزامنة...';
      subtitle = 'يتم رفع البيانات إلى الخادم';
    } else if (!isOnline && pendingCount > 0) {
      bg = Colors.orange.shade800;
      icon = Icons.cloud_off;
      title = 'غير متصل بالإنترنت';
      subtitle = '$pendingCount عملية محفوظة محلياً — ستُرفع تلقائياً عند الاتصال';
    } else if (!isOnline) {
      bg = Colors.grey.shade800;
      icon = Icons.cloud_off_outlined;
      title = 'غير متصل بالإنترنت';
      subtitle = 'لا توجد عمليات معلقة — جميع البيانات محفوظة';
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
          BoxShadow(color: bg.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))
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
  const _InfoRow({required this.icon, required this.label, required this.value});

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
          Text(label,
              style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
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
                color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold),
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

  const _QueueItemCard({
    required this.item,
    required this.operationLabel,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final date = intl.DateFormat('MM/dd hh:mm a').format(item.createdAt.toLocal());

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
                  style:
                      TextStyle(color: Colors.white38, fontSize: 11.sp)),
              if (item.retryCount > 0) ...[
                SizedBox(width: 12.w),
                Icon(Icons.replay, color: Colors.orange, size: 13.sp),
                SizedBox(width: 4.w),
                Text('محاولة ${item.retryCount}',
                    style:
                        TextStyle(color: Colors.orange, fontSize: 11.sp)),
              ],
            ],
          ),
          if (item.lastError != null && item.lastError!.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                item.lastError!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 11.sp),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
