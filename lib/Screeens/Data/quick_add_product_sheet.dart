import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Opens a bottom sheet to create a product in Firestore without leaving the invoice.
/// Returns the saved product map (including [id]) or null if cancelled.
Future<Map<String, dynamic>?> showQuickAddProductSheet(
  BuildContext context, {
  String? initialName,
  bool showRetailOption = false,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (_) => _QuickAddProductSheet(
      initialName: initialName,
      showRetailOption: showRetailOption,
    ),
  );
}

class _QuickAddProductSheet extends StatefulWidget {
  final String? initialName;
  final bool showRetailOption;

  const _QuickAddProductSheet({
    this.initialName,
    required this.showRetailOption,
  });

  @override
  State<_QuickAddProductSheet> createState() => _QuickAddProductSheetState();
}

class _QuickAddProductSheetState extends State<_QuickAddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final _descCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sp1Ctrl = TextEditingController();
  final _sp2Ctrl = TextEditingController();
  final _sp3Ctrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  bool _retail = false;
  bool _onDemand = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _costCtrl.dispose();
    _sp1Ctrl.dispose();
    _sp2Ctrl.dispose();
    _sp3Ctrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  String _normalizeName(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  double _optionalDouble(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0.0;
    return double.tryParse(text) ?? 0.0;
  }

  Future<bool> _productExists(String name) async {
    final q = await FirebaseFirestore.instance
        .collection('products')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    final name = _normalizeName(_nameCtrl.text);
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      if (await _productExists(name)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المنتج موجود بالفعل')),
        );
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('products')
          .orderBy('randomNumber', descending: true)
          .limit(1)
          .get();
      int nextRandom = 1;
      if (snap.docs.isNotEmpty) {
        nextRandom =
            ((snap.docs.first['randomNumber'] ?? 0) as num).toInt() + 1;
      }

      final descText = _descCtrl.text.trim();
      final data = <String, dynamic>{
        'name': name,
        'description': descText.isNotEmpty ? descText : null,
        'sellingPrice1': _optionalDouble(_sp1Ctrl),
        'sellingPrice2': _optionalDouble(_sp2Ctrl),
        'sellingPrice3': _optionalDouble(_sp3Ctrl),
        'costPrice': _optionalDouble(_costCtrl),
        'quantity': _optionalDouble(_qtyCtrl),
        'alertAmount': 0.0,
        'randomNumber': nextRandom,
        'department': '',
        'onDemand': _onDemand,
        'retail': widget.showRetailOption && _retail,
      };

      final ref =
          await FirebaseFirestore.instance.collection('products').add(data);
      await ref.update({'id': ref.id});

      if (!mounted) return;
      Navigator.pop(context, {...data, 'id': ref.id});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      ),
      validator: (v) {
        final text = v?.trim() ?? '';
        if (required && text.isEmpty) return 'هذا الحقل مطلوب';
        if (isNumber && text.isNotEmpty && double.tryParse(text) == null) {
          return 'يرجى إدخال رقم صالح';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.w,
          right: 16.w,
          top: 16.h,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16.h,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        'إضافة منتج جديد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 48.w),
                  ],
                ),
                SizedBox(height: 8.h),
                _field('اسم المنتج', _nameCtrl, required: true),
                SizedBox(height: 10.h),
                _field('الوصف', _descCtrl),
                SizedBox(height: 10.h),
                _field('سعر التكلفة', _costCtrl, isNumber: true),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(
                        child: _field('سعر بيع 1', _sp1Ctrl, isNumber: true)),
                    SizedBox(width: 8.w),
                    Expanded(
                        child: _field('سعر بيع 2', _sp2Ctrl, isNumber: true)),
                    SizedBox(width: 8.w),
                    Expanded(
                        child: _field('سعر بيع 3', _sp3Ctrl, isNumber: true)),
                  ],
                ),
                SizedBox(height: 10.h),
                _field('الكمية الحالية', _qtyCtrl, isNumber: true),
                if (widget.showRetailOption) ...[
                  SizedBox(height: 4.h),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('قطاعي', style: TextStyle(fontSize: 15.sp)),
                    value: _retail,
                    onChanged: _isSaving
                        ? null
                        : (v) => setState(() => _retail = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('حسب الطلب', style: TextStyle(fontSize: 15.sp)),
                  value: _onDemand,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _onDemand = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.75),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 22.w,
                          height: 22.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'حفظ وإضافة للفاتورة',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
