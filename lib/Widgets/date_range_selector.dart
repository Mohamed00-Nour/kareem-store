import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

Widget dateRangePickerTheme(BuildContext context, Widget? child) => Theme(
      data: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(primary: Colors.orange),
      ),
      child: child!,
    );

class DateRangeSelector extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const DateRangeSelector({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DateRangeButton(
            label: 'من',
            date: startDate,
            onTap: onPickStart,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: DateRangeButton(
            label: 'إلى',
            date: endDate,
            onTap: onPickEnd,
          ),
        ),
      ],
    );
  }
}

class DateRangeButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const DateRangeButton({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.orange.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16.sp, color: Colors.orange),
            SizedBox(width: 6.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.black.withOpacity(0.5))),
                  Text(
                    date != null
                        ? '${date!.day}/${date!.month}/${date!.year}'
                        : 'اختر تاريخ',
                    style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withOpacity(0.75)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
