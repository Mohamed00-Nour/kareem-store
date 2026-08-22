import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/Expenses.dart';
import '../Services/header_helper.dart';
import '../Services/printer_settings_service.dart';

class ExpensesDetails extends StatefulWidget {
  @override
  _ExpensesDetailsState createState() => _ExpensesDetailsState();
}

class _ExpensesDetailsState extends State<ExpensesDetails> {
  late Stream<List<Expenses>> _expensesStream;
  double _totalExpenses = 0.0;
  String? selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _expensesStream = _fetchExpenses();
    _calculateTotalExpenses();
  }

  Stream<List<Expenses>> _fetchExpenses() {
    return FirebaseFirestore.instance
        .collection('expenses')
        .orderBy('date', descending: true)
        .orderBy('time', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Expenses.fromMap(
              doc.data() as Map<String, dynamic>,
              id: doc.id,
            ))
            .toList());
  }

  void _calculateTotalExpenses() {
    FirebaseFirestore.instance
        .collection('expenses')
        .snapshots()
        .listen((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += double.tryParse(doc['value']) ?? 0.0;
      }
      setState(() {
        _totalExpenses = total;
      });
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _editExpense(Expenses expense) {
    _showEditDialog(expense, selectedDate);
  }

  Future<void> _selectDate(BuildContext context) async {
    final int currentYear = DateTime.now().year;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(currentYear, 1, 1),
      lastDate: DateTime(currentYear, 12, 31),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.orange.withOpacity(0.7),
            hintColor: Colors.orange.withOpacity(0.7),
            colorScheme: const ColorScheme.light(primary: Colors.orange),
            buttonTheme:
                const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme:
                const TextSelectionThemeData(cursorColor: Colors.black),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        selectedDate = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  void _showEditDialog(Expenses? expense, String? selectedDate) {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController nameController =
        TextEditingController(text: expense?.name ?? '');
    final TextEditingController valueController =
        TextEditingController(text: expense?.value ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black12.withOpacity(0.8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إضافة النثريات',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                Form(
                  key: _formKey,
                  child: Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Column(
                      children: [
                        Card(
                          margin: const EdgeInsets.all(8),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              keyboardType: TextInputType.text,
                              controller: nameController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.perm_identity_outlined),
                                hintText: 'أدخل إسم النثريات',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل إسم النثريات';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        Card(
                          margin: const EdgeInsets.all(8),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              controller: valueController,
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.attach_money_outlined),
                                labelStyle: TextStyle(
                                  color: Colors.black,
                                ),
                                hintText: 'أدخل المبلغ',
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'من فضلك أدخل المبلغ';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('إلغاء',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          if (expense == null) {
                            final newExpense = Expenses(
                              id: FirebaseFirestore.instance
                                  .collection('expenses')
                                  .doc()
                                  .id,
                              category: nameController.text.trim(),
                              date: selectedDate ?? '',
                              value: valueController.text,
                            );
                            await FirebaseFirestore.instance
                                .collection('expenses')
                                .doc(newExpense.id)
                                .set({
                              ...newExpense.toMap(),
                              'time': FieldValue.serverTimestamp(),
                            });
                            _showSnackBar('تم إضافة النثريات بنجاح');
                          } else {
                            await FirebaseFirestore.instance
                                .collection('expenses')
                                .doc(expense.id)
                                .update({
                              'category': nameController.text.trim(),
                              'name': nameController.text.trim(),
                              'date': selectedDate ?? '',
                              'value': valueController.text,
                              'time': FieldValue.serverTimestamp(),
                            });
                            _showSnackBar('تم تعديل النثريات بنجاح');
                          }
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('حفظ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteExpense(Expenses expense) async {
    await FirebaseFirestore.instance
        .collection('expenses')
        .doc(expense.id)
        .delete();
    _showSnackBar('تم حذف النثريات بنجاح');
    _calculateTotalExpenses();
  }

  Future<void> _generatePdfReport(List<Expenses> expenses) async {
    setState(() {
      _isLoading = true;
    });

    final settings = await PrinterSettingsService.load();
    final logoFile = HeaderHelper.getLogoFile(settings);
    final logoPdfImage = logoFile != null ? pw.MemoryImage(logoFile.readAsBytesSync()) : null;
    final headerLines = HeaderHelper.getHeaderLines(settings);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logoPdfImage != null) ...[
                pw.Center(
                  child: pw.Container(
                    height: 50,
                    child: pw.Image(logoPdfImage, fit: pw.BoxFit.contain),
                  ),
                ),
                pw.SizedBox(height: 6),
              ],
              for (final line in headerLines) ...[
                pw.Center(
                  child: pw.Text(
                    line,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 2),
              ],
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'تقرير النثريات',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'إجمالي النثريات: $_totalExpenses',
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          );
        },
      ),
    );

    try {
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/expenses_report.pdf');
      await file.writeAsBytes(await pdf.save());

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: 'expenses_report.pdf',
      );

      if (outputFile != null) {
        await file.copy(outputFile);
        _showSnackBar('PDF saved to $outputFile');
      }
    } catch (e) {
      _showSnackBar('Error saving PDF: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle headTableTextStyle = TextStyle(
      fontSize: 18.sp,
      fontWeight: FontWeight.bold,
      color: Colors.black.withOpacity(0.7),
    );

    return Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل النثريات'),
        ),
        body: Padding(
          padding: EdgeInsets.all(10.w),
          child: SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'إجمالي النثريات: $_totalExpenses',
                    style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: () => _selectDate(context),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      selectedDate ?? 'اختر التاريخ',
                      style: TextStyle(
                        fontSize: 18.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  ElevatedButton(
                    onPressed: selectedDate != null
                        ? () => _showEditDialog(null, selectedDate)
                        : null,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: Text(
                      'إضافة',
                      style: TextStyle(
                        fontSize: 18.sp,
                        color: Colors.white.withOpacity(1),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  ElevatedButton(
                    onPressed: () async {
                      final expenses = await _expensesStream.first;
                      await _generatePdfReport(expenses);
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: Colors.black.withOpacity(0.7),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : Text(
                            'تصدير PDF',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: Colors.white.withOpacity(1),
                            ),
                          ),
                  ),
                  SizedBox(height: 10.h),
                  StreamBuilder<List<Expenses>>(
                    stream: _expensesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator(
                          color: Colors.orange.withOpacity(0.8),
                        );
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text('لا يوجد نثريات',
                              style: TextStyle(fontSize: 18)),
                        );
                      } else {
                        final expenses = snapshot.data!;
                        final groupedExpenses = <String, List<Expenses>>{};

                        for (var expense in expenses) {
                          if (!groupedExpenses.containsKey(expense.date)) {
                            groupedExpenses[expense.date] = [];
                          }
                          groupedExpenses[expense.date]!.add(expense);
                        }

                        return Column(
                          children: groupedExpenses.entries.map((entry) {
                            return Column(
                              children: [
                                Center(
                                  child: Container(
                                    width: double.infinity,
                                    height: 1.h,
                                    color: Colors.green,
                                    margin:
                                        EdgeInsets.symmetric(vertical: 10.h),
                                  ),
                                ),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: [
                                      DataColumn(
                                          label: Text('التاريخ',
                                              style: headTableTextStyle)),
                                      DataColumn(
                                          label: Text('الإسم',
                                              style: headTableTextStyle)),
                                      DataColumn(
                                          label: Text('المبلغ',
                                              style: headTableTextStyle)),
                                      DataColumn(
                                          label: Text('تعديل أو حذف',
                                              style: headTableTextStyle)),
                                    ],
                                    rows: entry.value.map<DataRow>((expense) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(expense.date,
                                              style:
                                                  TextStyle(fontSize: 14.sp))),
                                          DataCell(Text(expense.name,
                                              style:
                                                  TextStyle(fontSize: 14.sp))),
                                          DataCell(Text(expense.value,
                                              style:
                                                  TextStyle(fontSize: 14.sp))),
                                          DataCell(
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.edit,
                                                      size: 18.sp),
                                                  onPressed: () =>
                                                      _editExpense(expense),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.delete,
                                                      size: 18.sp),
                                                  onPressed: () =>
                                                      _deleteExpense(expense),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
