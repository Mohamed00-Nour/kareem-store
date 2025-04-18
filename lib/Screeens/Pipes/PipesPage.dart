import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../Widgets/main-cards.dart';
import 'AddPipePage.dart';
import 'DecreasePipePage.dart';
import 'PipeListPage.dart';


class PipesPage extends StatelessWidget {
  const PipesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('المواسير',
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
                        builder: (context) => const AddPipePage()));
                  },
                ),
                CardWidget(
                  imagePath: 'assets/images/minus gred.png',
                  text: 'صرف',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const DecreasePipePage()));
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
                      builder: (context) =>  PipeListPage()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
