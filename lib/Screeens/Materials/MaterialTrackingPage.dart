import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Widgets/main-cards.dart';
import '../Suoervisors/SupervisorListScreen.dart';
import 'AddMaterialPage.dart';
import 'DecreaseMaterialPage.dart';
import 'MaterialListPage.dart';
import 'MaterialTrackingScreen.dart';
import 'SupervisorDataScreen.dart';

class MaterialTrackingPage extends StatelessWidget {
  final List<String> _materials = [ 'Material 2', 'Material 3'];

   MaterialTrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: Text('تتبع المواد الخام',
            style: TextStyle(color: Colors.white, fontSize: 20.sp)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CardWidget(
                  imagePath: 'assets/images/plus.png',
                  text: 'إضافة خامة',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const AddMaterialPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/minus gred.png',
                  text: 'صرف خامة',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const DecreaseMaterialPage()));
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CardWidget(
                  imagePath: 'assets/images/shipping.png',
                  text: 'الكمية الحالية',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const MaterialListPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/expense.png',
                  text: 'تتبع الخامة',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => MaterialTrackingScreen(materials: _materials)));
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),
            CardWidget(
              imagePath: 'assets/images/director.png',
              text: 'تتبع المشرفين',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => SupervisorListScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}