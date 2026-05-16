import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BestProductsReportPage extends StatefulWidget {
  const BestProductsReportPage({super.key});

  @override
  State<BestProductsReportPage> createState() =>
      _BestProductsReportPageState();
}

class _BestProductsReportPageState extends State<BestProductsReportPage>
    with SingleTickerProviderStateMixin {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  late TabController _tabController;

  List<_ProductStat> _byQuantity = [];
  List<_ProductStat> _byProfit = [];
  List<_ProductStat> _byRevenue = [];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showProductSuggestions = false;
  bool _loadingProducts = true;

  List<String> _productNames = [];
  String? _selectedProduct;

  List<String> get _filteredProductNames {
    if (_searchQuery.isEmpty) return _productNames;
    final q = _searchQuery.toLowerCase();
    return _productNames
        .where((name) => name.toLowerCase().contains(q))
        .toList();
  }

  List<_ProductStat> _filterStats(List<_ProductStat> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  void _selectProduct(String name) {
    setState(() {
      _selectedProduct = name;
      _searchController.text = name;
      _searchQuery = name;
      _showProductSuggestions = false;
    });
    _searchFocusNode.unfocus();
  }

  void _clearProductSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedProduct = null;
      _showProductSuggestions = false;
    });
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
    if (_startDate == null || _endDate == null) return;
    setState(() => _loading = true);

    final start =
        DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(
        _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);

    try {
      // Fetch all products cost prices
      final productsSnap =
          await FirebaseFirestore.instance.collection('products').get();
      final Map<String, double> costPrices = {};
      for (final doc in productsSnap.docs) {
        costPrices[doc['name'] as String] =
            (doc.data()['costPrice'] ?? 0.0).toDouble();
      }

      // Fetch invoices in range
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final Map<String, _ProductStat> statsMap = {};

      for (final doc in invoicesSnap.docs) {
        final products =
            (doc.data()['products'] as List<dynamic>?) ?? [];
        for (final p in products) {
          final pMap = p as Map<String, dynamic>;
          final name = pMap['product'] as String? ?? '';
          final qty =
              double.tryParse(pMap['amount']?.toString() ?? '0') ?? 0;
          final revenue = (pMap['total'] ?? 0.0).toDouble();
          final cost = (costPrices[name] ?? 0.0) * qty;

          if (statsMap.containsKey(name)) {
            statsMap[name] = _ProductStat(
              name: name,
              totalQuantity: statsMap[name]!.totalQuantity + qty,
              totalRevenue: statsMap[name]!.totalRevenue + revenue,
              totalProfit: statsMap[name]!.totalProfit + (revenue - cost),
            );
          } else {
            statsMap[name] = _ProductStat(
              name: name,
              totalQuantity: qty,
              totalRevenue: revenue,
              totalProfit: revenue - cost,
            );
          }
        }
      }

      final all = statsMap.values.toList();

      setState(() {
        _byQuantity = List.from(all)
          ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
        _byRevenue = List.from(all)
          ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
        _byProfit = List.from(all)
          ..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
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
            'أفضل المنتجات',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.white70,
            labelStyle:
                TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'الكمية'),
              Tab(text: 'الإيرادات'),
              Tab(text: 'الأرباح'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(12.w),
              child: Column(
                children: [
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
                  SizedBox(height: 10.h),
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
                              icon: const Icon(Icons.clear,
                                  color: Colors.black54),
                              onPressed: _clearProductSearch,
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            BorderSide(color: Colors.grey.shade400),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide:
                            const BorderSide(color: Colors.orange),
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
                        }
                      });
                    },
                  ),
                  if (_loadingProducts)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: const Center(
                          child: CircularProgressIndicator()),
                    )
                  else if (_showProductSuggestions && _searchQuery.isNotEmpty)
                    Container(
                      margin: EdgeInsets.only(top: 6.h),
                      constraints: BoxConstraints(maxHeight: 180.h),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10.r),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.5)),
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
                      padding: EdgeInsets.only(top: 6.h),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.amber.shade700.withOpacity(0.9),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      onPressed: (_startDate != null &&
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
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ProductList(
                    stats: _filterStats(_byQuantity),
                    valueLabel: 'الكمية المباعة',
                    valueGetter: (s) =>
                        '${s.totalQuantity.toStringAsFixed(1)} وحدة',
                    rankColor: Colors.orange,
                  ),
                  _ProductList(
                    stats: _filterStats(_byRevenue),
                    valueLabel: 'الإيرادات',
                    valueGetter: (s) =>
                        '${s.totalRevenue.toStringAsFixed(2)} ج.م',
                    rankColor: Colors.blue,
                  ),
                  _ProductList(
                    stats: _filterStats(_byProfit),
                    valueLabel: 'الأرباح',
                    valueGetter: (s) =>
                        '${s.totalProfit.toStringAsFixed(2)} ج.م',
                    rankColor: Colors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductStat {
  final String name;
  final double totalQuantity;
  final double totalRevenue;
  final double totalProfit;

  const _ProductStat({
    required this.name,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.totalProfit,
  });
}

class _ProductList extends StatelessWidget {
  final List<_ProductStat> stats;
  final String valueLabel;
  final String Function(_ProductStat) valueGetter;
  final Color rankColor;

  const _ProductList({
    required this.stats,
    required this.valueLabel,
    required this.valueGetter,
    required this.rankColor,
  });

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return Center(
        child: Text(
          'لا توجد بيانات\nاختر فترة زمنية واضغط عرض التقرير',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14.sp, color: Colors.black.withOpacity(0.5)),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      itemCount: stats.length,
      itemBuilder: (ctx, index) {
        final stat = stats[index];
        final rank = index + 1;
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.symmetric(vertical: 5.h),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding:
                EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
            child: Row(
              children: [
                Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? rankColor.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                          color: rank <= 3
                              ? rankColor
                              : Colors.black.withOpacity(0.5)),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(stat.name,
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.8))),
                ),
                Text(
                  valueGetter(stat),
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: rankColor),
                ),
              ],
            ),
          ),
        );
      },
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
