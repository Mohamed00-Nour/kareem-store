import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../Services/invoice_number_utils.dart';

class ProductReportPage extends StatefulWidget {
  const ProductReportPage({super.key});

  @override
  State<ProductReportPage> createState() => _ProductReportPageState();
}

class _ProductReportPageState extends State<ProductReportPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  bool _loadingProducts = true;

  List<String> _productNames = [];
  String? _selectedProduct;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showProductSuggestions = false;

  _ProductStats? _stats;
  bool _usedLegacyCostFallback = false;

  List<String> get _filteredProductNames {
    if (_searchQuery.isEmpty) return _productNames;
    final q = _searchQuery.toLowerCase();
    return _productNames
        .where((name) => name.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchProductNames();
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() => _showProductSuggestions = false);
      } else if (_searchQuery.isNotEmpty) {
        setState(() => _showProductSuggestions = true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _selectProduct(String name) {
    setState(() {
      _selectedProduct = name;
      _searchController.text = name;
      _searchQuery = name;
      _showProductSuggestions = false;
      _stats = null;
      _usedLegacyCostFallback = false;
    });
    _searchFocusNode.unfocus();
  }

  void _clearProductSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedProduct = null;
      _stats = null;
      _usedLegacyCostFallback = false;
      _showProductSuggestions = false;
    });
  }

  Future<void> _fetchProductNames() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('products').get();
      setState(() {
        _productNames =
            snap.docs.map((d) => d['name'] as String).toList()..sort();
        _loadingProducts = false;
      });
    } catch (_) {
      setState(() => _loadingProducts = false);
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.orange),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => isStart ? _startDate = picked : _endDate = picked);
    }
  }

  Future<void> _fetchReport() async {
    if (_selectedProduct == null || _startDate == null || _endDate == null)
      return;
    setState(() => _loading = true);

    final start =
        DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(
        _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);

    try {
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      double totalQuantity = 0;
      double totalRevenue = 0;
      double totalCost = 0;
      int invoiceCount = 0;
      var usedLegacyFallback = false;

      // Fallback for old invoice lines without frozen costPrice on the line.
      double catalogCost = 0;
      final productSnap = await FirebaseFirestore.instance
          .collection('products')
          .where('name', isEqualTo: _selectedProduct)
          .limit(1)
          .get();
      if (productSnap.docs.isNotEmpty) {
        catalogCost = invoiceNum(productSnap.docs.first.data()['costPrice']);
      }

      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        final products = (data['products'] as List<dynamic>?) ?? [];
        for (final p in products) {
          final pMap = Map<String, dynamic>.from(p as Map);
          if (invoiceCatalogProductName(pMap) != _selectedProduct) continue;

          final qty = invoiceNum(pMap['amount']);
          final revenue = invoiceNum(pMap['total']);
          if (!invoiceLineHasFrozenCost(pMap)) {
            usedLegacyFallback = true;
          }
          final lineCost = invoiceLineTotalCost(
            pMap,
            catalogUnitCost: catalogCost,
          );

          totalQuantity += qty;
          totalRevenue += revenue;
          totalCost += lineCost;
          invoiceCount++;
        }
      }

      setState(() {
        _usedLegacyCostFallback = usedLegacyFallback;
        _stats = _ProductStats(
          productName: _selectedProduct!,
          totalQuantitySold: totalQuantity,
          totalRevenue: totalRevenue,
          totalCost: totalCost,
          totalProfit: totalRevenue - totalCost,
          invoiceCount: invoiceCount,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'تقرير منتج',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج...',
                  hintTextDirection: TextDirection.rtl,
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.black54),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54),
                          onPressed: _clearProductSearch,
                        )
                      : null,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w, vertical: 10.h),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: const BorderSide(color: Colors.orange),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.85),
                ),
                onTap: () {
                  if (_searchQuery.isNotEmpty) {
                    setState(() => _showProductSuggestions = true);
                  }
                },
                onChanged: (v) {
                  setState(() {
                    _searchQuery = v.trim();
                    _showProductSuggestions = _searchQuery.isNotEmpty;
                    if (_selectedProduct != null &&
                        _selectedProduct != _searchQuery) {
                      _selectedProduct = null;
                      _stats = null;
                      _usedLegacyCostFallback = false;
                    }
                  });
                },
              ),
              if (_loadingProducts)
                Padding(
                  padding: EdgeInsets.only(top: 10.h),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (_showProductSuggestions && _searchQuery.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(top: 6.h),
                  constraints: BoxConstraints(maxHeight: 220.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _filteredProductNames.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(14.w),
                          child: Text(
                            'لا توجد نتائج للبحث',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(vertical: 4.h),
                          itemCount: _filteredProductNames.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.grey.withOpacity(0.25),
                          ),
                          itemBuilder: (context, index) {
                            final name = _filteredProductNames[index];
                            final selected = name == _selectedProduct;
                            return ListTile(
                              dense: true,
                              title: Text(
                                name,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? Colors.orange.shade800
                                      : Colors.black87,
                                ),
                              ),
                              trailing: selected
                                  ? Icon(Icons.check_circle,
                                      color: Colors.orange, size: 20.sp)
                                  : null,
                              onTap: () => _selectProduct(name),
                            );
                          },
                        ),
                )
              else if (_selectedProduct != null)
                Padding(
                  padding: EdgeInsets.only(top: 8.h),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 18.sp, color: Colors.orange.shade700),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          'المنتج: $_selectedProduct',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 12.h),
              // Date range
              Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                        label: 'من',
                        date: _startDate,
                        onTap: () => _pickDate(true)),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _DatePickerButton(
                        label: 'إلى',
                        date: _endDate,
                        onTap: () => _pickDate(false)),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.85),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                  onPressed: (_selectedProduct != null &&
                          _startDate != null &&
                          _endDate != null &&
                          !_loading)
                      ? _fetchReport
                      : null,
                  child: _loading
                      ? SizedBox(
                          width: 20.w,
                          height: 20.h,
                          child: const CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('عرض التقرير',
                          style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              if (_stats != null) ...[
                SizedBox(height: 20.h),
                if (_usedLegacyCostFallback)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: Text(
                      'تنبيه: بعض الفواتير القديمة لا تحتوي تكلفة محفوظة — '
                      'تم استخدام التكلفة الحالية لتلك الأسطر فقط.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                _ReportResultCard(stats: _stats!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductStats {
  final String productName;
  final double totalQuantitySold;
  final double totalRevenue;
  final double totalCost;
  final double totalProfit;
  final int invoiceCount;

  _ProductStats({
    required this.productName,
    required this.totalQuantitySold,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    required this.invoiceCount,
  });
}

class _ReportResultCard extends StatelessWidget {
  final _ProductStats stats;

  const _ReportResultCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(14.r),
        ),
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 5.w,
                    height: 18.h,
                    decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4.r))),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(stats.productName,
                      style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.8))),
                ),
              ],
            ),
            Divider(height: 16.h, color: Colors.grey.withOpacity(0.3)),
            _Row(
                label: 'عدد مرات البيع',
                value: '${stats.invoiceCount}',
                unit: 'مرة'),
            _Row(
                label: 'الكمية المباعة',
                value: stats.totalQuantitySold.toStringAsFixed(2),
                unit: 'وحدة'),
            _Row(
                label: 'إجمالي الإيرادات',
                value: stats.totalRevenue.toStringAsFixed(2),
                unit: 'ج.م'),
            _Row(
                label: 'إجمالي التكلفة',
                value: stats.totalCost.toStringAsFixed(2),
                unit: 'ج.م'),
            _Row(
                label: 'إجمالي الربح',
                value: stats.totalProfit.toStringAsFixed(2),
                unit: 'ج.م',
                highlight: stats.totalProfit >= 0),
            if (stats.totalQuantitySold > 0)
              _Row(
                  label: 'متوسط سعر البيع',
                  value:
                      (stats.totalRevenue / stats.totalQuantitySold)
                          .toStringAsFixed(2),
                  unit: 'ج.م / وحدة'),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool highlight;

  const _Row(
      {required this.label,
      required this.value,
      required this.unit,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.black.withOpacity(0.6))),
          Row(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: highlight
                        ? Colors.green.shade700
                        : Colors.black.withOpacity(0.8))),
            SizedBox(width: 4.w),
            Text(unit,
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.black.withOpacity(0.5))),
          ]),
        ],
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DatePickerButton(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.orange.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16.sp, color: Colors.orange),
            SizedBox(width: 6.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.black.withOpacity(0.5))),
                Text(
                  date != null
                      ? '${date!.day}/${date!.month}/${date!.year}'
                      : 'اختر تاريخ',
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black.withOpacity(0.75)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
