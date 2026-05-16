import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class InventoryReportPage extends StatefulWidget {
  const InventoryReportPage({super.key});

  @override
  State<InventoryReportPage> createState() => _InventoryReportPageState();
}

class _InventoryReportPageState extends State<InventoryReportPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  late TabController _tabController;

  double _totalStockValue = 0;
  double _totalSellingValue = 0;
  int _totalProducts = 0;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;

  List<_StockItem> _lowStockItems = [];
  List<_StockItem> _allItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchInventory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchInventory() async {
    setState(() => _loading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('products').get();

      double totalCostValue = 0;
      double totalSellingValue = 0;
      int lowStockCount = 0;
      int outOfStockCount = 0;
      final List<_StockItem> low = [];
      final List<_StockItem> all = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';
        final qty = (data['quantity'] ?? 0.0).toDouble();
        final costPrice = (data['costPrice'] ?? 0.0).toDouble();
        final sellingPrice = (data['sellingPrice1'] ?? 0.0).toDouble();
        final alertAmount = (data['alertAmount'] ?? 0).toDouble();
        final department = data['department'] as String? ?? '';

        totalCostValue += qty * costPrice;
        totalSellingValue += qty * sellingPrice;

        final item = _StockItem(
          name: name,
          quantity: qty,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          alertAmount: alertAmount,
          department: department,
        );

        all.add(item);

        if (qty == 0) {
          outOfStockCount++;
          low.add(item);
        } else if (alertAmount > 0 && qty <= alertAmount) {
          lowStockCount++;
          low.add(item);
        }
      }

      all.sort((a, b) => a.name.compareTo(b.name));
      low.sort((a, b) => a.quantity.compareTo(b.quantity));

      setState(() {
        _totalStockValue = totalCostValue;
        _totalSellingValue = totalSellingValue;
        _totalProducts = snap.docs.length;
        _lowStockCount = lowStockCount;
        _outOfStockCount = outOfStockCount;
        _lowStockItems = low;
        _allItems = all;
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
            'تقرير المخزون',
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
              Tab(text: 'ملخص المخزون'),
              Tab(text: 'تنبيهات المخزون'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Summary + all items
                  SingleChildScrollView(
                    padding: EdgeInsets.all(12.w),
                    child: Column(
                      children: [
                        // Summary cards row
                        Row(
                          children: [
                            Expanded(
                              child: _MiniCard(
                                label: 'إجمالي المنتجات',
                                value: '$_totalProducts',
                                unit: 'منتج',
                                color: Colors.purple,
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: _MiniCard(
                                label: 'منخفض المخزون',
                                value: '$_lowStockCount',
                                unit: 'منتج',
                                color: Colors.orange,
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: _MiniCard(
                                label: 'نفذ المخزون',
                                value: '$_outOfStockCount',
                                unit: 'منتج',
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        _BigValueCard(
                          label: 'قيمة المخزون بسعر التكلفة',
                          value: _totalStockValue.toStringAsFixed(2),
                          unit: 'ج.م',
                          color: Colors.purple,
                        ),
                        SizedBox(height: 10.h),
                        _BigValueCard(
                          label: 'قيمة المخزون بسعر البيع',
                          value: _totalSellingValue.toStringAsFixed(2),
                          unit: 'ج.م',
                          color: Colors.green,
                        ),
                        SizedBox(height: 10.h),
                        _BigValueCard(
                          label: 'الربح المتوقع من المخزون',
                          value: (_totalSellingValue - _totalStockValue)
                              .toStringAsFixed(2),
                          unit: 'ج.م',
                          color: Colors.teal,
                        ),
                        SizedBox(height: 16.h),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'جميع المنتجات',
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black.withOpacity(0.7)),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        ..._allItems.map((item) => _StockItemCard(item: item)),
                      ],
                    ),
                  ),
                  // Tab 2: Low stock alerts
                  _lowStockItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 60.sp, color: Colors.green),
                              SizedBox(height: 12.h),
                              Text(
                                'جميع المنتجات بمستوى مخزون جيد',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.black.withOpacity(0.6)),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(12.w),
                          itemCount: _lowStockItems.length,
                          itemBuilder: (ctx, i) =>
                              _StockItemCard(item: _lowStockItems[i]),
                        ),
                ],
              ),
      ),
    );
  }
}

class _StockItem {
  final String name;
  final double quantity;
  final double costPrice;
  final double sellingPrice;
  final double alertAmount;
  final String department;

  const _StockItem({
    required this.name,
    required this.quantity,
    required this.costPrice,
    required this.sellingPrice,
    required this.alertAmount,
    required this.department,
  });
}

class _MiniCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MiniCard(
      {required this.label,
      required this.value,
      required this.unit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12.r),
        ),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(unit,
                style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.black.withOpacity(0.5))),
            SizedBox(height: 4.h),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.sp, color: Colors.black.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}

class _BigValueCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _BigValueCard(
      {required this.label,
      required this.value,
      required this.unit,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(14.r),
        ),
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.black.withOpacity(0.65))),
            Row(
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: color)),
                SizedBox(width: 4.w),
                Text(unit,
                    style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.black.withOpacity(0.5))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StockItemCard extends StatelessWidget {
  final _StockItem item;

  const _StockItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = item.quantity == 0;
    final isLow = item.alertAmount > 0 && item.quantity <= item.alertAmount;
    Color statusColor = Colors.green;
    String statusText = 'متوفر';
    if (isOutOfStock) {
      statusColor = Colors.red;
      statusText = 'نفذ';
    } else if (isLow) {
      statusColor = Colors.orange;
      statusText = 'منخفض';
    }

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      margin: EdgeInsets.symmetric(vertical: 4.h),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
              color: statusColor.withOpacity(isLow || isOutOfStock ? 0.4 : 0),
              width: 1.2),
        ),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.8))),
                  if (item.department.isNotEmpty)
                    Text(item.department,
                        style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.black.withOpacity(0.45))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text(
                      '${item.quantity.toStringAsFixed(1)} وحدة',
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black.withOpacity(0.75)),
                    ),
                    SizedBox(width: 6.w),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(statusText,
                          style: TextStyle(
                              fontSize: 10.sp,
                              color: statusColor,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                Text(
                  'تكلفة: ${item.costPrice.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.black.withOpacity(0.45)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
