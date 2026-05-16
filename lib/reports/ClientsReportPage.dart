import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ClientsReportPage extends StatefulWidget {
  const ClientsReportPage({super.key});

  @override
  State<ClientsReportPage> createState() => _ClientsReportPageState();
}

class _ClientsReportPageState extends State<ClientsReportPage>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late TabController _tabController;

  DateTime? _startDate;
  DateTime? _endDate;

  List<_ClientStat> _bySales = [];
  List<_ClientStat> _byProfit = [];

  double _grandSales = 0;
  double _grandProfit = 0;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Default: current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _fetchReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
          colorScheme: const ColorScheme.light(
            primary: Colors.black87,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = DateTime(picked.year, picked.month, picked.day);
        } else {
          _endDate =
              DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Future<void> _fetchReport() async {
    if (_startDate == null || _endDate == null) return;
    setState(() => _loading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!))
          .get();

      final Map<String, _ClientStat> map = {};

      for (final doc in snap.docs) {
        final data = doc.data();
        final clientName = (data['clientName'] ?? '').toString();
        if (clientName.isEmpty) continue;

        final totalSum = (data['totalSum'] ?? 0.0) is num
            ? (data['totalSum'] as num).toDouble()
            : double.tryParse(data['totalSum'].toString()) ?? 0.0;
        final profit = (data['profitMargin'] ?? 0.0) is num
            ? (data['profitMargin'] as num).toDouble()
            : double.tryParse(data['profitMargin'].toString()) ?? 0.0;

        if (map.containsKey(clientName)) {
          final prev = map[clientName]!;
          map[clientName] = _ClientStat(
            name: clientName,
            totalSales: prev.totalSales + totalSum,
            totalProfit: prev.totalProfit + profit,
            invoiceCount: prev.invoiceCount + 1,
          );
        } else {
          map[clientName] = _ClientStat(
            name: clientName,
            totalSales: totalSum,
            totalProfit: profit,
            invoiceCount: 1,
          );
        }
      }

      final all = map.values.toList();

      setState(() {
        _bySales = List.from(all)
          ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
        _byProfit = List.from(all)
          ..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
        _grandSales =
            all.fold(0.0, (s, c) => s + c.totalSales);
        _grandProfit =
            all.fold(0.0, (s, c) => s + c.totalProfit);
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

  String _fmt(DateTime? d) =>
      d == null ? '---' : DateFormat('yyyy/MM/dd').format(d);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffeeeced),
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'تقرير العملاء',
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
              Tab(text: 'أعلى مبيعاً'),
              Tab(text: 'أعلى أرباحاً'),
            ],
          ),
        ),
        body: Column(
          children: [
            // ── Date range picker ──────────────────────────────────
            Container(
              color: Colors.white,
              padding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              child: Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'من',
                      value: _fmt(_startDate),
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _DateButton(
                      label: 'إلى',
                      value: _fmt(_endDate),
                      onTap: () => _pickDate(false),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: 14.w, vertical: 12.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r)),
                    ),
                    onPressed: _loading ? null : _fetchReport,
                    child: Text('بحث', style: TextStyle(fontSize: 13.sp)),
                  ),
                ],
              ),
            ),
            // ── Search bar ────────────────────────────────────────
            Container(
              color: Colors.white,
              padding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'ابحث عن عميل...',
                  hintTextDirection: TextDirection.rtl,
                  prefixIcon: const Icon(Icons.search, color: Colors.black54),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
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
                    borderSide: const BorderSide(color: Colors.black87),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
            // ── Totals summary ─────────────────────────────────────
            if (!_loading && _bySales.isNotEmpty)
              Container(
                color: Colors.black.withOpacity(0.7),
                padding: EdgeInsets.symmetric(
                    horizontal: 16.w, vertical: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryChip(
                      label: 'إجمالي المبيعات',
                      value: '${_grandSales.toStringAsFixed(2)} ج.م',
                      color: Colors.orange,
                    ),
                    _SummaryChip(
                      label: 'إجمالي الأرباح',
                      value: '${_grandProfit.toStringAsFixed(2)} ج.م',
                      color: Colors.greenAccent,
                    ),
                    _SummaryChip(
                      label: 'عدد العملاء',
                      value: '${_bySales.length}',
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            // ── Content ────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _ClientList(
                          clients: _searchQuery.isEmpty
                              ? _bySales
                              : _bySales
                                  .where((c) => c.name
                                      .toLowerCase()
                                      .contains(_searchQuery.toLowerCase()))
                                  .toList(),
                          sortBy: 'sales',
                        ),
                        _ClientList(
                          clients: _searchQuery.isEmpty
                              ? _byProfit
                              : _byProfit
                                  .where((c) => c.name
                                      .toLowerCase()
                                      .contains(_searchQuery.toLowerCase()))
                                  .toList(),
                          sortBy: 'profit',
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

// ─── Data model ──────────────────────────────────────────────────────────────

class _ClientStat {
  final String name;
  final double totalSales;
  final double totalProfit;
  final int invoiceCount;

  const _ClientStat({
    required this.name,
    required this.totalSales,
    required this.totalProfit,
    required this.invoiceCount,
  });
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateButton(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10.r),
          color: Colors.grey.shade50,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 13.sp, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.black.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 13.sp,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 2.h),
        Text(label,
            style: TextStyle(
                color: Colors.white70, fontSize: 10.sp)),
      ],
    );
  }
}

class _ClientList extends StatelessWidget {
  final List<_ClientStat> clients;
  final String sortBy; // 'sales' or 'profit'

  const _ClientList({required this.clients, required this.sortBy});

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) {
      return Center(
        child: Text(
          'لا توجد بيانات في هذه الفترة',
          style: TextStyle(
              fontSize: 14.sp, color: Colors.black.withOpacity(0.5)),
        ),
      );
    }

    final rankColor = sortBy == 'sales' ? Colors.orange : Colors.green;

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      itemCount: clients.length,
      itemBuilder: (ctx, index) {
        final c = clients[index];
        final rank = index + 1;
        final primaryValue = sortBy == 'sales' ? c.totalSales : c.totalProfit;
        final primaryLabel =
            sortBy == 'sales' ? 'إجمالي المبيعات' : 'إجمالي الأرباح';
        final profitPct = c.totalSales > 0
            ? (c.totalProfit / c.totalSales * 100)
            : 0.0;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.symmetric(vertical: 5.h),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding:
                EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 34.w,
                  height: 34.w,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? rankColor.withOpacity(0.15)
                        : Colors.grey.withOpacity(0.1),
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
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.black.withOpacity(0.85))),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          _Chip(
                            label: 'المبيعات',
                            value:
                                '${c.totalSales.toStringAsFixed(2)} ج.م',
                            color: Colors.orange.shade700,
                          ),
                          SizedBox(width: 8.w),
                          _Chip(
                            label: 'الأرباح',
                            value:
                                '${c.totalProfit.toStringAsFixed(2)} ج.م',
                            color: c.totalProfit >= 0
                                ? Colors.green.shade700
                                : Colors.red,
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          _Chip(
                            label: 'الفواتير',
                            value: '${c.invoiceCount}',
                            color: Colors.blue.shade700,
                          ),
                          SizedBox(width: 8.w),
                          _Chip(
                            label: 'هامش الربح',
                            value: '${profitPct.toStringAsFixed(1)}%',
                            color: profitPct >= 20
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Primary value big display
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${primaryValue.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: rankColor),
                    ),
                    Text(
                      'ج.م',
                      style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.black.withOpacity(0.4)),
                    ),
                    Text(
                      primaryLabel,
                      style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.black.withOpacity(0.4)),
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
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Chip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withOpacity(0.3), width: 0.7),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                  fontSize: 10.sp,
                  color: Colors.black.withOpacity(0.5)),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }
}

