import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../Widgets/main-cards.dart';
import 'AddInjectedProductPage.dart';
import 'DecreaseInjectedProductPage.dart';
import 'CurrentBalancePage.dart';

class InjectedProductPage extends StatelessWidget {
  const InjectedProductPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الحقن',
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
                  text: 'إضافة',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const AddInjectedProductPage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/minus gred.png',
                  text: 'صرف',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const DecreaseInjectedProductPage()));
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Center(
              child: CardWidget(
                imagePath: 'assets/images/shipping.png',
                text: 'الرصيد الحالي',
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const CurrentBalancePage()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}