import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../sync/connectivity_service.dart';
import '../../sync/sync_queue_manager.dart';
import 'sync_dashboard_screen.dart';

/// App-Bar action widget that shows real-time sync & connectivity status.
///
/// States:
///  🟢  Online & all synced          → green dot icon
///  🔄  Syncing (queue processing)   → animated spinning icon
///  🟠  Offline (N pending items)    → orange badge with count
///
/// Tapping opens [SyncDashboardScreen].
class SyncStatusBadge extends StatefulWidget {
  const SyncStatusBadge({super.key});

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  bool _isOnline = ConnectivityService.instance.isOnline;
  int _pendingCount = SyncQueueManager.instance.pendingCount;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    ConnectivityService.instance.onlineStream.listen((online) {
      if (!mounted) return;
      setState(() {
        _isOnline = online;
        _isSyncing = online && SyncQueueManager.instance.hasPending;
        _pendingCount = SyncQueueManager.instance.pendingCount;
      });
    });

    // Refresh pending count periodically
    Stream.periodic(const Duration(seconds: 3)).listen((_) {
      if (!mounted) return;
      final count = SyncQueueManager.instance.pendingCount;
      if (count != _pendingCount) {
        setState(() {
          _pendingCount = count;
          _isSyncing = _isOnline && count > 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltipText,
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SyncDashboardScreen()),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              SizedBox(width: 4.w),
              Text(
                _labelText,
                style: TextStyle(
                  color: _labelColor,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_isSyncing) {
      return RotationTransition(
        turns: _spinController,
        child: Icon(Icons.sync, color: Colors.lightBlueAccent, size: 18.sp),
      );
    }
    if (!_isOnline) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 20.sp),
          if (_pendingCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: BoxConstraints(minWidth: 14.w, minHeight: 14.h),
                child: Text(
                  '$_pendingCount',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      );
    }
    // Online & synced
    return Icon(Icons.cloud_done_outlined, color: Colors.greenAccent, size: 20.sp);
  }

  String get _tooltipText {
    if (_isSyncing) return 'جارٍ المزامنة...';
    if (!_isOnline && _pendingCount > 0) return 'غير متصل — $_pendingCount عملية معلقة';
    if (!_isOnline) return 'غير متصل بالإنترنت';
    return 'متصل — كل البيانات محدّثة';
  }

  String get _labelText {
    if (_isSyncing) return 'مزامنة...';
    if (!_isOnline && _pendingCount > 0) return '$_pendingCount معلّق';
    if (!_isOnline) return 'غير متصل';
    return 'متصل';
  }

  Color get _labelColor {
    if (_isSyncing) return Colors.lightBlueAccent;
    if (!_isOnline) return Colors.orange;
    return Colors.greenAccent;
  }
}
