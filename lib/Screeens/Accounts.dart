import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../Widgets/main-cards.dart';
import 'AppartmentsDetails.dart';
import 'Borrow.dart';
import 'ExpensesDetails.dart';
import 'RequestSpareParts.dart';
import 'SparePartsDetails.dart';
import 'medicines.dart';

class Accounts extends StatelessWidget {
  const Accounts({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeced),
      appBar: AppBar(
        backgroundColor: const Color(0xffeeeced),
        title: Text(
          'الحسابات',
          style: TextStyle(
            fontSize: 22.sp, // Smaller font size
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 0.w), // Smaller padding
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w), // Smaller padding
                  child: Row(
                    children: [
                      CardWidget(
                        imagePath: 'assets/images/money.png',
                        text: 'السلف',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => Borrow()));
                        },
                      ),
                      CardWidget(
                        imagePath: 'assets/images/paper-pin.png',
                        text: 'النثريات',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => ExpensesDetails()));
                        },
                      ),
                      CardWidget(
                        imagePath: 'assets/images/spare-parts.png',
                        text: 'قطع الغيار ',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => SparePartsDetails()));
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w), // Smaller padding
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CardWidget(
                        imagePath: 'assets/images/appartement.png',
                        text: 'السكن',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => AppartmentsDetails()));
                        },
                      ),
                      CardWidget(
                        imagePath: 'assets/images/medicine.png',
                        text: 'العلاج',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => MedicineWidget()));
                        },
                      ),
                      CardWidget(
                        imagePath: 'assets/images/request.png',
                        text: 'طلب قطع غيار',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => RequestSpareParts()));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}