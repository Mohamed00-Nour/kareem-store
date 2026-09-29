import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BoxChangesScreen extends StatefulWidget {
  const BoxChangesScreen({super.key});

  @override
  State<BoxChangesScreen> createState() => _BoxChangesScreenState();
}

class _BoxChangesScreenState extends State<BoxChangesScreen> {
  static const int _pageSize = 50;

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _changes = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  static const List<String> _arabicMonths = [
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
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('box')
        .doc('mainBox')
        .collection('changes')
        .where(
          'date',
          isGreaterThanOrEqualTo: DateTime(
            _selectedYear,
            _selectedMonth,
            1,
          ),
        )
        .where(
          'date',
          isLessThan: DateTime(_selectedYear, _selectedMonth + 1, 1),
        )
        .orderBy('date', descending: true)
        .limit(_pageSize);
    if (_lastDocument != null) {
      query = query.startAfterDocument(_lastDocument!);
    }
    return query;
  }

  Future<void> _loadPage({required bool reset}) async {
    if (reset) {
      setState(() {
        _changes.clear();
        _lastDocument = null;
        _hasMore = true;
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final page = await _query().get();
      if (!mounted) return;
      setState(() {
        _changes.addAll(page.docs);
        _lastDocument = page.docs.isEmpty ? _lastDocument : page.docs.last;
        _hasMore = page.docs.length == _pageSize;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  DateTime? _dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تغييرات الصندوق',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black.withOpacity(0.7),
        actions: [
          DropdownButton<int>(
            value: _selectedMonth,
            dropdownColor: Colors.black87,
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox.shrink(),
            items: List.generate(
              12,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text(_arabicMonths[index]),
              ),
            ),
            onChanged: (value) {
              if (value == null || value == _selectedMonth) return;
              _selectedMonth = value;
              _loadPage(reset: true);
            },
          ),
          SizedBox(width: 10.w),
          DropdownButton<int>(
            value: _selectedYear,
            dropdownColor: Colors.black87,
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox.shrink(),
            items: List.generate(
              10,
              (index) {
                final year = DateTime.now().year - index;
                return DropdownMenuItem(
                  value: year,
                  child: Text(year.toString()),
                );
              },
            ),
            onChanged: (value) {
              if (value == null || value == _selectedYear) return;
              _selectedYear = value;
              _loadPage(reset: true);
            },
          ),
          SizedBox(width: 12.w),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadPage(reset: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_changes.isEmpty && _error != null) {
      return ListView(
        children: [
          SizedBox(height: 180.h),
          Center(child: Text('تعذر تحميل تغييرات الصندوق: $_error')),
          Center(
            child: TextButton(
              onPressed: () => _loadPage(reset: true),
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      );
    }
    if (_changes.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: 180.h),
          Center(
            child: Text(
              'لا توجد تغييرات للصندوق في هذا الشهر',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('القيمة')),
              DataColumn(label: Text('النوع')),
              DataColumn(label: Text('اسم العميل')),
              DataColumn(label: Text('رقم الفاتورة')),
            ],
            rows: _changes.map((doc) {
              final change = doc.data();
              final date = _dateOf(change['date']);
              final formattedDate = date == null
                  ? 'غير متوفر'
                  : '${date.day}/${date.month}/${date.year}';
              return DataRow(
                cells: [
                  DataCell(Text(formattedDate)),
                  DataCell(Text((change['value'] ?? 0).toString())),
                  DataCell(
                    Text(change['type'] == 'decrement' ? 'صرف' : 'إضافة'),
                  ),
                  DataCell(Text((change['name'] ?? 'غير معروف').toString())),
                  DataCell(
                    Text((change['invoiceNumber'] ?? 'غير معروف').toString()),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Text(
              'تعذر تحميل المزيد: $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (_hasMore)
          Center(
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: () => _loadPage(reset: false),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('تحميل المزيد'),
                    ),
            ),
          ),
      ],
    );
  }
}
