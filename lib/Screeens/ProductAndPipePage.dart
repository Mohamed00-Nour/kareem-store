import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'ProductListPage.dart';
import 'Pipes/PipeListPage.dart';
import '../Widgets/main-cards.dart';
import 'Data/DataEntryScreen.dart';

class ProductAndPipePage extends StatelessWidget {
  const ProductAndPipePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        title: Text(
          'المنتجات والمواسير',
          style: TextStyle(fontSize: 20.sp, color: Colors.white),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Padding(
        padding: EdgeInsets.all(10.w),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CardWidget(
                imagePath: 'assets/images/boxes.png',
                text: 'المنتجات',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProductListPage()),
                  );
                },
              ),
              SizedBox(width: 20.w),
              CardWidget(
                imagePath: 'assets/images/pipe.png',
                text: 'المواسير',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PipeListPage()),
                  );
                },
              ),

            ],
          ),
        ),
      ),
    );
  }
}