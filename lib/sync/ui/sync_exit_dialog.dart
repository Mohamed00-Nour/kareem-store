import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Asks whether the application should close while an upload is in progress.
///
/// Returning `false` keeps the application open. Returning `true` allows the
/// caller to close it. Pending operations remain durable in either case.
Future<bool> showSyncAwareExitDialog(
  BuildContext context, {
  required bool uploading,
  required int unfinishedCount,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xffead1ac),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0.r),
          ),
          title: Text(
            'الخروج من التطبيق',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontWeight: FontWeight.bold,
              fontSize: 20.sp,
            ),
          ),
          content: Text(
            uploading
                ? 'يوجد $unfinishedCount عملية جارٍ رفعها أو بانتظار دورها. '
                    'يمكنك الإغلاق بأمان وستُستكمل العمليات عند فتح التطبيق مرة أخرى، '
                    'لكنها لن تظهر على الأجهزة الأخرى حتى يكتمل الرفع.'
                : 'هل تريد حقا الخروج من التطبيق ؟',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontSize: 18.sp,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                uploading ? 'البقاء حتى اكتمال الرفع' : 'لا',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                uploading ? 'إغلاق الآن' : 'نعم',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
