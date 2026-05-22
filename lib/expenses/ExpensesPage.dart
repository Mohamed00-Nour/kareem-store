import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../Widgets/date_range_selector.dart';
import '../models/Expenses.dart';
import 'expense_service.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String? _filterCategory;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  List<Expenses> _allExpenses = [];
  bool _expensesLoading = true;
  String? _expensesError;
  StreamSubscription<List<Expenses>>? _expensesSub;

  bool get _hasActiveFilters =>
      _filterCategory != null ||
      _periodStart != null ||
      _periodEnd != null ||
      _searchQuery.trim().isNotEmpty;

  List<Expenses> get _filteredExpenses => ExpenseService.filterExpenses(
        _allExpenses,
        category: _filterCategory,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        searchQuery: _searchQuery,
      );

  @override
  void initState() {
    super.initState();
    ExpenseService.ensureDefaultCategories();
    _expensesSub = ExpenseService.expensesStream().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _allExpenses = list;
          _expensesLoading = false;
          _expensesError = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _expensesError = e.toString();
          _expensesLoading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
  }

  Future<void> _pickPeriodDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_periodStart ?? DateTime.now())
          : (_periodEnd ?? _periodStart ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: dateRangePickerTheme,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _periodStart = picked;
        if (_periodEnd != null && _periodEnd!.isBefore(_periodStart!)) {
          _periodEnd = _periodStart;
        }
      } else {
        _periodEnd = picked;
        if (_periodStart != null && _periodEnd!.isBefore(_periodStart!)) {
          _periodStart = _periodEnd;
        }
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _filterCategory = null;
      _periodStart = null;
      _periodEnd = null;
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  String _summaryTitle(int count) {
    if (!_hasActiveFilters) {
      return _filterCategory == null
          ? 'إجمالي المصروفات'
          : 'إجمالي: $_filterCategory';
    }
    final parts = <String>['نتيجة الاستعلام'];
    if (_periodStart != null || _periodEnd != null) {
      final from = _periodStart != null
          ? DateFormat('dd/MM/yyyy').format(_periodStart!)
          : '…';
      final to = _periodEnd != null
          ? DateFormat('dd/MM/yyyy').format(_periodEnd!)
          : '…';
      parts.add('$from — $to');
    }
    return '${parts.join(' · ')} ($count)';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showCategoryManager() async {
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إدارة فئات المصروفات'),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder(
              stream: ExpenseService.categoriesDocsStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Text('لا توجد فئات');
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final name = doc.data()['name']?.toString() ?? '';
                    final isDefault = doc.data()['isDefault'] == true;
                    return ListTile(
                      title: Text(name),
                      trailing: isDefault
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await ExpenseService.deleteCategory(doc.id);
                              },
                            ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('فئة مصروف جديدة'),
          content: TextField(
            controller: ctrl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(hintText: 'مثال: مصاريف الصيانة'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                await ExpenseService.addCategory(name);
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack('تمت إضافة الفئة');
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpenseForm({Expenses? expense}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseFormSheet(expense: expense),
    );
    if (message != null && mounted) {
      _showSnack(message);
    }
  }

  Future<void> _confirmDelete(Expenses expense) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المصروف'),
          content: Text('حذف "${expense.category}" بمبلغ ${expense.amount}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ExpenseService.deleteExpense(expense.id);
      _showSnack('تم الحذف');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'المصروفات',
            style: TextStyle(color: Colors.white, fontSize: 20.sp),
          ),
          actions: [
            IconButton(
              tooltip: 'فئات المصروفات',
              icon: const Icon(Icons.category_outlined, color: Colors.white),
              onPressed: _showCategoryManager,
            ),
            IconButton(
              tooltip: 'فئة جديدة',
              icon: const Icon(Icons.add_box_outlined, color: Colors.white),
              onPressed: _showAddCategoryDialog,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.orange.shade700,
          onPressed: () => _showExpenseForm(),
          child: const Icon(Icons.add),
        ),
        body: _expensesLoading
            ? const Center(child: CircularProgressIndicator())
            : _expensesError != null
                ? Center(child: Text('خطأ: $_expensesError'))
                : Builder(
                    builder: (context) {
                      final filtered = _filteredExpenses;
                      final total =
                          filtered.fold<double>(0, (s, e) => s + e.amount);

                      return Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 0),
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _summaryTitle(filtered.length),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '${total.toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _hasActiveFilters
                            ? '${filtered.length} مصروف'
                            : 'تُخصم من هامش الربح تلقائياً',
                        style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    textAlign: TextAlign.right,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'بحث (الفئة، المبلغ، الملاحظات، الحقول…)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 12.h,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'فترة الاستعلام',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      DateRangeSelector(
                        startDate: _periodStart,
                        endDate: _periodEnd,
                        onPickStart: () => _pickPeriodDate(true),
                        onPickEnd: () => _pickPeriodDate(false),
                      ),
                      if (_hasActiveFilters) ...[
                        SizedBox(height: 8.h),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off, size: 18),
                            label: const Text('مسح الفلاتر'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  height: 44.h,
                  child: StreamBuilder<List<String>>(
                    stream: ExpenseService.categoriesStream(),
                    builder: (context, catSnap) {
                      final cats = catSnap.data ?? [];
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 6.w),
                            child: FilterChip(
                              label: const Text('الكل'),
                              selected: _filterCategory == null,
                              onSelected: (_) =>
                                  setState(() => _filterCategory = null),
                            ),
                          ),
                          ...cats.map(
                            (c) => Padding(
                              padding: EdgeInsets.only(left: 6.w),
                              child: FilterChip(
                                label: Text(c),
                                selected: _filterCategory == c,
                                onSelected: (_) =>
                                    setState(() => _filterCategory = c),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _hasActiveFilters
                                ? 'لا توجد مصروفات لهذا الاستعلام'
                                : 'لا توجد مصروفات',
                            style: TextStyle(fontSize: 16.sp),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 12.w),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            final attrs = e.attributes.entries
                                .where((x) => x.key.isNotEmpty)
                                .toList();
                            return Card(
                              margin: EdgeInsets.only(bottom: 8.h),
                              child: ListTile(
                                title: Text(
                                  e.category,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15.sp,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e.date} — ${e.amount.toStringAsFixed(2)} ج.م'),
                                    if (e.notes.isNotEmpty) Text(e.notes),
                                    ...attrs.map(
                                      (a) => Text('${a.key}: ${a.value}'),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          _showExpenseForm(expense: e),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () => _confirmDelete(e),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _AttributeFieldRow {
  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;

  _AttributeFieldRow({String key = '', String value = ''})
      : keyCtrl = TextEditingController(text: key),
        valueCtrl = TextEditingController(text: value);

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _ExpenseFormSheet extends StatefulWidget {
  final Expenses? expense;

  const _ExpenseFormSheet({this.expense});

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _newCategoryCtrl;
  late DateTime _selectedDate;
  String? _selectedCategory;
  List<String> _categories = List<String>.from(ExpenseService.defaultCategories);
  final List<_AttributeFieldRow> _attrRows = [];
  StreamSubscription<List<String>>? _categoriesSub;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountCtrl = TextEditingController(
      text: e != null && e.amount > 0 ? e.amount.toString() : '',
    );
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _newCategoryCtrl = TextEditingController();
    _selectedDate =
        ExpenseService.expenseDateFromData(e?.toMap() ?? {}) ?? DateTime.now();
    if (e != null && e.category.isNotEmpty) {
      _selectedCategory = e.category;
    }
    e?.attributes.forEach((k, v) {
      _attrRows.add(_AttributeFieldRow(key: k, value: v));
    });
    _categoriesSub = ExpenseService.categoriesStream().listen((cats) {
      if (!mounted) return;
      setState(() {
        _categories = cats.isEmpty
            ? List<String>.from(ExpenseService.defaultCategories)
            : cats;
      });
    });
  }

  @override
  void dispose() {
    _categoriesSub?.cancel();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _newCategoryCtrl.dispose();
    for (final row in _attrRows) {
      row.dispose();
    }
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 22.sp) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r),
        borderSide: BorderSide(color: Colors.orange.shade700, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
    );
  }

  void _addAttrRow() {
    setState(() => _attrRows.add(_AttributeFieldRow()));
  }

  void _removeAttrRow(int index) {
    final row = _attrRows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;

    final category = _newCategoryCtrl.text.trim().isNotEmpty
        ? _newCategoryCtrl.text.trim()
        : (_selectedCategory ?? '').trim();
    if (category.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار أو إدخال فئة المصروف')),
        );
      }
      return;
    }
    final amount =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
        );
      }
      return;
    }

    final attributes = <String, String>{};
    for (final row in _attrRows) {
      final k = row.keyCtrl.text.trim();
      final v = row.valueCtrl.text.trim();
      if (k.isNotEmpty) attributes[k] = v;
    }

    setState(() => _saving = true);
    try {
      await ExpenseService.saveExpense(
        id: widget.expense?.id,
        category: category,
        amount: amount,
        date: _selectedDate,
        notes: _notesCtrl.text,
        attributes: attributes,
      );
      if (!mounted) return;
      final msg = widget.expense == null
          ? 'تم إضافة المصروف'
          : 'تم تحديث المصروف';
      Navigator.pop(context, msg);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final isEdit = widget.expense != null;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: const Color(0xffeeeced),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: 10.h),
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 8.w, 8.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'تعديل مصروف' : 'إضافة مصروف',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الفئة',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory != null &&
                                _categories.contains(_selectedCategory)
                            ? _selectedCategory
                            : null,
                        decoration: _fieldDecoration(
                          label: 'اختر الفئة',
                          icon: Icons.category_outlined,
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _selectedCategory = v),
                      ),
                      SizedBox(height: 12.h),
                      TextField(
                        controller: _newCategoryCtrl,
                        enabled: !_saving,
                        textAlign: TextAlign.right,
                        decoration: _fieldDecoration(
                          label: 'أو فئة جديدة',
                          hint: 'مثال: مصاريف الصيانة',
                          icon: Icons.add_circle_outline,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      TextField(
                        controller: _amountCtrl,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: _fieldDecoration(
                          label: 'المبلغ',
                          hint: '0.00 ج.م',
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      InkWell(
                        onTap: _saving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (picked != null && mounted) {
                                  setState(() => _selectedDate = picked);
                                }
                              },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 14.h,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: Colors.orange.shade700,
                                size: 22.sp,
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'التاريخ',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('yyyy-MM-dd')
                                          .format(_selectedDate),
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_left,
                                color: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      TextField(
                        controller: _notesCtrl,
                        enabled: !_saving,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        decoration: _fieldDecoration(
                          label: 'ملاحظات',
                          hint: 'اختياري',
                          icon: Icons.notes_outlined,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Row(
                        children: [
                          Text(
                            'حقول إضافية',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _saving ? null : _addAttrRow,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('حقل'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                      for (var i = 0; i < _attrRows.length; i++)
                        Padding(
                          key: ObjectKey(_attrRows[i]),
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _attrRows[i].keyCtrl,
                                  enabled: !_saving,
                                  textAlign: TextAlign.right,
                                  decoration: _fieldDecoration(label: 'الاسم'),
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: TextField(
                                  controller: _attrRows[i].valueCtrl,
                                  enabled: !_saving,
                                  textAlign: TextAlign.right,
                                  decoration:
                                      _fieldDecoration(label: 'القيمة'),
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    _saving ? null : () => _removeAttrRow(i),
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red.shade400,
                                  size: 22.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        child: Text('إلغاء', style: TextStyle(fontSize: 15.sp)),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          elevation: 0,
                        ),
                        child: _saving
                            ? SizedBox(
                                width: 22.w,
                                height: 22.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'حفظ المصروف',
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
