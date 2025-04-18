import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DecreaseMaterialPage extends StatefulWidget {
  const DecreaseMaterialPage({super.key});

  @override
  _DecreaseMaterialPageState createState() => _DecreaseMaterialPageState();
}

class _DecreaseMaterialPageState extends State<DecreaseMaterialPage> {
  final List<String> _materials = [];
  final List<String> _supervisors = [];
  String? _selectedMaterial;
  String? _selectedResponsible;
  DateTime? _selectedDate;
  final List<Map<String, dynamic>> _addedMaterials = [];
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int? _editingIndex;
  bool _dataSaved = false;
  bool _dataModified = false;
  bool _isSaving = false;
  bool _isFetchingMaterials = true;
  bool _isFetchingSupervisors = true;

  @override
  void initState() {
    super.initState();
    _fetchMaterials();
    _fetchSupervisors();
  }

  Future<void> _fetchMaterials() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('data').doc('lists').get();
      if (doc.exists) {
        setState(() {
          _materials.addAll(List<String>.from(doc['materials']));
          _isFetchingMaterials = false;
        });
      }
    } catch (e) {
      print('Error fetching materials: $e');
      setState(() {
        _isFetchingMaterials = false;
      });
    }
  }

  Future<void> _fetchSupervisors() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('data').doc('lists').get();
      if (doc.exists) {
        setState(() {
          _supervisors.addAll(List<String>.from(doc['supervisors']));
          _isFetchingSupervisors = false;
        });
      }
    } catch (e) {
      print('Error fetching supervisors: $e');
      setState(() {
        _isFetchingSupervisors = false;
      });
    }
  }

  void _pickDate() async {
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
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
            textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = "${picked.toLocal()}".split(' ')[0];
        _dataModified = true;
      });
    }
  }

  void _selectResponsible() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: const Text('اختر المسئول', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              children: _supervisors.map((String responsible) {
                return ListTile(
                  title: Text(responsible, style: TextStyle(color: Colors.white)),
                  onTap: () {
                    setState(() {
                      _selectedResponsible = responsible;
                      _dataModified = true;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _addMaterial() {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار التاريخ')),
        );
        return;
      }
      if (_selectedResponsible == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار المسئول')),
        );
        return;
      }
      setState(() {
        bool materialExists = false;
        for (var material in _addedMaterials) {
          if (material['material'] == _selectedMaterial) {
            material['amount'] = (int.parse(material['amount']) + int.parse(_amountController.text)).toString();
            materialExists = true;
            break;
          }
        }
        if (!materialExists) {
          _addedMaterials.add({
            'material': _selectedMaterial,
            'date': _selectedDate,
            'responsible': _selectedResponsible,
            'amount': _amountController.text,
          });
        }
        _selectedMaterial = null;
        _amountController.clear();
        _dataModified = true;
      });
    }
  }

  void _editMaterial(int index) {
    setState(() {
      _selectedMaterial = _addedMaterials[index]['material'];
      _selectedDate = _addedMaterials[index]['date'];
      _selectedResponsible = _addedMaterials[index]['responsible'];
      _amountController.text = _addedMaterials[index]['amount'];
      _dateController.text = "${_selectedDate!.toLocal()}".split(' ')[0];
      _editingIndex = index;
    });
  }

  void _deleteMaterial(int index) {
    setState(() {
      _addedMaterials.removeAt(index);
      _dataModified = true;
    });
  }

  void _saveData() async {
    if (!_dataModified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data already saved')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    for (var material in _addedMaterials) {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('materials')
          .where('material', isEqualTo: material['material'])
          .get();

      if (query.docs.isNotEmpty) {
        // Update existing material
        for (var doc in query.docs) {
          int existingAmount = int.parse(doc['amount']);
          int newAmount = existingAmount - int.parse(material['amount']);
          await FirebaseFirestore.instance
              .collection('materials')
              .doc(doc.id)
              .update({
            'amount': newAmount.toString(),
          });

          // Add change to sub-collection
          await FirebaseFirestore.instance
              .collection('materials')
              .doc(doc.id)
              .collection('changes')
              .add({
            'date': material['date'],
            'amount': material['amount'],
            'type': 'decrease',
            'responsible': material['responsible'], // Ensure responsible is saved
          });
        }
      } else {
        // Add new material
        DocumentReference newMaterialRef = await FirebaseFirestore.instance.collection('materials').add({
          'material': material['material'],
          'date': material['date'],
          'responsible': material['responsible'],
          'amount': material['amount'],
        });

        // Add change to sub-collection
        await newMaterialRef.collection('changes').add({
          'date': material['date'],
          'amount': material['amount'],
          'type': 'decrease',
          'responsible': material['responsible'], // Ensure responsible is saved
        });
      }
    }

    setState(() {
      _dataSaved = true;
      _dataModified = false;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحفظ بنجاح'),),
    );
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
        title: Text('صرف مادة', style: TextStyle(fontSize: 20.sp, color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.7),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(10.w),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Card(
                          margin: EdgeInsets.symmetric(horizontal: 5.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: IconButton(
                            icon: Icon(Icons.calendar_month, color: Colors.black.withOpacity(0.7)),
                            onPressed: _pickDate,
                          ),
                        ),
                        Stack(
                          children: [
                            Card(
                              margin: EdgeInsets.symmetric(horizontal: 5.w, vertical: 8.h),
                              elevation: 2,
                              color: Colors.orange.withOpacity(0.8),
                              child: IconButton(
                                icon: Icon(Icons.perm_identity, color: Colors.black.withOpacity(0.7)),
                                onPressed: _selectResponsible,
                              ),
                            ),
                            if (_isFetchingSupervisors)
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Stack(
                      children: [
                        Card(
                          margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                          elevation: 2,
                          color: Colors.orange.withOpacity(0.8),
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                suffixIcon: Icon(Icons.shopping_cart),
                                hintText: 'اختر المادة',
                                border: InputBorder.none,
                              ),
                              value: _selectedMaterial,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedMaterial = newValue;
                                  _dataModified = true;
                                });
                              },
                              items: _materials.map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'يرجى اختيار المادة';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        if (_isFetchingMaterials)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 40.w, vertical: 8.h),
                      elevation: 2,
                      color: Colors.orange.withOpacity(0.8),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: TextFormField(
                          controller: _amountController,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.format_list_numbered),
                            hintText: 'أدخل الكمية',
                            border: InputBorder.none,
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال الكمية';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _dataModified = true;
                          },
                        ),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        onPressed: _addMaterial,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7),
                        ),
                        child: Text(
                          _editingIndex != null ? 'تحديث المادة' : 'إضافة مادة',
                          style: TextStyle(
                            fontSize: 18.sp,
                            color: Colors.white.withOpacity(1),
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('التاريخ', style: headTableTextStyle)),
                          DataColumn(label: Text('المسئول', style: headTableTextStyle)),
                          DataColumn(label: Text('المادة', style: headTableTextStyle)),
                          DataColumn(label: Text('الكمية', style: headTableTextStyle)),
                          DataColumn(label: Text('تعديل وحذف', style: headTableTextStyle)),
                        ],
                        rows: _addedMaterials.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, dynamic> material = entry.value;
                          return DataRow(cells: [
                            DataCell(Text(material['date'].toString().split(' ')[0], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(material['responsible'], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(material['material'], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Text(material['amount'], style: TextStyle(fontSize: 14.sp))),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _editMaterial(index),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteMaterial(index),
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        onPressed: _saveData,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          backgroundColor: Colors.black.withOpacity(0.7),
                        ),
                        child: Text(
                          'حفظ',
                          style: TextStyle(
                            fontSize: 20.sp,
                            color: Colors.white.withOpacity(1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.orange.withOpacity(0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}