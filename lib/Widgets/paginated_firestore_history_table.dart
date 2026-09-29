import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Bounded, user-driven reader for legacy Firestore history collections.
///
/// History is intentionally fetched with one-time cursor queries. Opening a
/// page reads at most [pageSize] documents and does not keep a billable
/// realtime listener alive while the screen is open.
class PaginatedFirestoreHistoryTable extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> collection;
  final bool showResponsible;
  final int pageSize;
  final String emptyText;
  final Map<String, String> typeLabels;

  const PaginatedFirestoreHistoryTable({
    super.key,
    required this.collection,
    this.showResponsible = false,
    this.pageSize = 50,
    this.emptyText = 'لا يوجد سجل متاح',
    this.typeLabels = const {
      'increase': 'إضافة',
      'decrease': 'صرف',
      'update': 'تحديث',
      'edit': 'تحديث',
    },
  });

  @override
  State<PaginatedFirestoreHistoryTable> createState() =>
      _PaginatedFirestoreHistoryTableState();
}

class _PaginatedFirestoreHistoryTableState
    extends State<PaginatedFirestoreHistoryTable> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _documents = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  Future<void> _loadPage({required bool reset}) async {
    if (reset) {
      setState(() {
        _documents.clear();
        _lastDocument = null;
        _loading = true;
        _hasMore = true;
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
      Query<Map<String, dynamic>> query = widget.collection
          .orderBy('date', descending: true)
          .limit(widget.pageSize);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      final page = await query.get();
      if (!mounted) return;
      setState(() {
        _documents.addAll(page.docs);
        _lastDocument = page.docs.isEmpty ? _lastDocument : page.docs.last;
        _hasMore = page.docs.length == widget.pageSize;
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

  String _formatDate(Object? value) {
    final DateTime? date = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : null;
    if (date == null) return 'غير متاح';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_documents.isEmpty && _error != null) {
      return _message(
        'تعذر تحميل السجل: $_error',
        retry: true,
      );
    }
    if (_documents.isEmpty) return _message(widget.emptyText);

    final columns = <DataColumn>[
      const DataColumn(label: Text('التاريخ')),
      if (widget.showResponsible) const DataColumn(label: Text('المسؤول')),
      const DataColumn(label: Text('الكمية')),
      const DataColumn(label: Text('النوع')),
    ];

    return RefreshIndicator(
      onRefresh: () => _loadPage(reset: true),
      child: ListView(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns,
              rows: _documents.map((document) {
                final data = document.data();
                final type = (data['type'] ?? '').toString();
                return DataRow(
                  cells: [
                    DataCell(Text(_formatDate(data['date']))),
                    if (widget.showResponsible)
                      DataCell(
                        Text((data['responsible'] ?? 'غير متاح').toString()),
                      ),
                    DataCell(Text((data['amount'] ?? 0).toString())),
                    DataCell(Text(widget.typeLabels[type] ?? type)),
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
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return ListView(
      children: [
        SizedBox(height: 160.h),
        Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
        ),
        if (retry)
          Center(
            child: TextButton(
              onPressed: () => _loadPage(reset: true),
              child: const Text('إعادة المحاولة'),
            ),
          ),
      ],
    );
  }
}
