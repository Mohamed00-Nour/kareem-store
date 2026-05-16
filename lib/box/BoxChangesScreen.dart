import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BoxChangesScreen extends StatefulWidget {
  const BoxChangesScreen({Key? key}) : super(key: key);

  @override
  _BoxChangesScreenState createState() => _BoxChangesScreenState();
}

class _BoxChangesScreenState extends State<BoxChangesScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  final List<String> _arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'تغييرات الصندوق',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Row(
              children: [
                DropdownButton<int>(
                  value: _selectedMonth,
                  dropdownColor: Colors.black.withOpacity(0.8),
                  style: const TextStyle(color: Colors.white),
                  items: List.generate(12, (index) {
                    return DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                        _arabicMonths[index],
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }),
                  onChanged: (value) {
                    setState(() {
                      _selectedMonth = value!;
                    });
                  },
                ),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: _selectedYear,
                  dropdownColor: Colors.black.withOpacity(0.8),
                  style: const TextStyle(color: Colors.white),
                  items: List.generate(10, (index) {
                    int year = DateTime.now().year - index;
                    return DropdownMenuItem(
                      value: year,
                      child: Text(
                        year.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }),
                  onChanged: (value) {
                    setState(() {
                      _selectedYear = value!;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: SingleChildScrollView(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('box')
              .doc('mainBox')
              .collection('changes')
              .where('date', isGreaterThanOrEqualTo: DateTime(_selectedYear, _selectedMonth, 1))
              .where('date', isLessThan: DateTime(_selectedYear, _selectedMonth + 1, 1))
              .orderBy('date', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(
                  color: Colors.orange.withOpacity(0.8),
                ),
              );
            } else if (snapshot.hasError) {
              return Center(
                child: Text('Error: ${snapshot.error}'),
              );
            } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Text(
                  'لا توجد تغييرات للصندوق في هذا الشهر',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                ),
              );
            }
        
            final changes = snapshot.data!.docs;
            print('عدد السجلات المعروضة: ${changes.length}');
        
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('القيمة')),
                  DataColumn(label: Text('النوع')),
                  DataColumn(label: Text('اسم العميل')),
                  DataColumn(label: Text('رقم الفاتورة')),
                ],
                rows: changes.map((doc) {
                  final change = doc.data() as Map<String, dynamic>;
                  final date = (change['date'] as Timestamp?)?.toDate();
                  final formattedDate = date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : 'غير متوفر';
                  final value = change['value'] ?? 0.0;
                  final type = change['type'] == 'decrement' ? 'صرف' : 'إضافة';
                  final clientName = change['name'] ?? 'غير معروف';
                  final invoiceNumber = change['invoiceNumber'] ?? 'غير معروف';
        
                  return DataRow(cells: [
                    DataCell(Text(formattedDate)),
                    DataCell(Text(value.toString())),
                    DataCell(Text(type)),
                    DataCell(Text(clientName)),
                    DataCell(Text(invoiceNumber.toString())),
                  ]);
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }
}