import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../Services/bluetooth_printer_service.dart';
import '../Services/printer_settings_service.dart';
import '../models/invoice_labels.dart';
import '../models/paired_bluetooth_device.dart';
import '../models/printer_settings.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  final _storeNameController = TextEditingController();
  final _storeAddressController = TextEditingController();
  final _storePhoneController = TextEditingController();
  final _salesFooterController = TextEditingController();
  final _a4FooterController = TextEditingController();
  final _textHeightController = TextEditingController(text: '10');
  final _macController = TextEditingController();
  final _fontSizeController = TextEditingController(text: '20');
  final _rightMarginController = TextEditingController(text: '0');
  final _bottomMarginController = TextEditingController(text: '0');

  PrinterConnectionType _connectionType = PrinterConnectionType.bluetooth;
  InvoiceLabels _labels = const InvoiceLabels();
  bool _showCustomerAddressAndPhone = false;
  bool _showPreviousCustomerDebt = false;
  bool _printProductNameOnSeparateLine = false;
  bool _showExpiryDateOnA4 = false;
  bool _showProductNumberOnA4 = false;
  bool _showProductDescription = false;
  bool _useA4WhenSharingInvoice = false;
  bool _printImmediatelyAfterSave = false;
  bool _showTaxQrOnInvoice = false;
  bool _showProductImageOnInvoice = false;
  ThermalPaperSize _paperSize = ThermalPaperSize.mm80;
  int _invoiceCopies = 1;
  int _thermalPrinterModel = 2;
  int _barcodePrinterModel = 1;
  int _paperCutCommand = 1;
  int _drawerOpenCommand = 1;
  String _deviceName = '';
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeAddressController.dispose();
    _storePhoneController.dispose();
    _salesFooterController.dispose();
    _a4FooterController.dispose();
    _textHeightController.dispose();
    _macController.dispose();
    _fontSizeController.dispose();
    _rightMarginController.dispose();
    _bottomMarginController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await PrinterSettingsService.load();
    if (!mounted) return;
    setState(() {
      _storeNameController.text = settings.receiptStoreName;
      _storeAddressController.text = settings.receiptStoreAddress;
      _storePhoneController.text = settings.receiptStorePhone;
      _salesFooterController.text = settings.salesInvoiceFooter;
      _a4FooterController.text = settings.a4ReportFooter;
      _textHeightController.text = settings.textHeightPosition.toString();
      _macController.text = settings.bluetoothMacAddress;
      _fontSizeController.text = settings.fontSize.toString();
      _connectionType = settings.connectionType;
      _paperSize = settings.paperSize;
      _invoiceCopies = settings.invoiceCopies;
      _thermalPrinterModel = settings.thermalPrinterModel;
      _barcodePrinterModel = settings.barcodePrinterModel;
      _paperCutCommand = settings.paperCutCommand;
      _drawerOpenCommand = settings.drawerOpenCommand;
      _deviceName = settings.bluetoothDeviceName;
      _rightMarginController.text = settings.rightMargin.toString();
      _bottomMarginController.text = settings.bottomMargin.toString();
      _labels = settings.labels;
      _showCustomerAddressAndPhone = settings.showCustomerAddressAndPhone;
      _showPreviousCustomerDebt = settings.showPreviousCustomerDebt;
      _printProductNameOnSeparateLine = settings.printProductNameOnSeparateLine;
      _showExpiryDateOnA4 = settings.showExpiryDateOnA4;
      _showProductNumberOnA4 = settings.showProductNumberOnA4;
      _showProductDescription = settings.showProductDescription;
      _useA4WhenSharingInvoice = settings.useA4WhenSharingInvoice;
      _printImmediatelyAfterSave = settings.printImmediatelyAfterSave;
      _showTaxQrOnInvoice = settings.showTaxQrOnInvoice;
      _showProductImageOnInvoice = settings.showProductImageOnInvoice;
      _loading = false;
    });
  }

  PrinterSettings _currentSettings() {
    return PrinterSettings(
      receiptStoreName: _storeNameController.text.trim(),
      receiptStoreAddress: _storeAddressController.text.trim(),
      receiptStorePhone: _storePhoneController.text.trim(),
      salesInvoiceFooter: _salesFooterController.text.trim(),
      a4ReportFooter: _a4FooterController.text.trim(),
      textHeightPosition: int.tryParse(_textHeightController.text) ?? 10,
      connectionType: _connectionType,
      bluetoothMacAddress: _macController.text.trim(),
      bluetoothDeviceName: _deviceName,
      paperSize: _paperSize,
      invoiceCopies: _invoiceCopies,
      thermalPrinterModel: _thermalPrinterModel,
      barcodePrinterModel: _barcodePrinterModel,
      paperCutCommand: _paperCutCommand,
      drawerOpenCommand: _drawerOpenCommand,
      fontSize: int.tryParse(_fontSizeController.text) ?? 20,
      rightMargin: int.tryParse(_rightMarginController.text) ?? 0,
      bottomMargin: int.tryParse(_bottomMarginController.text) ?? 0,
      showCustomerAddressAndPhone: _showCustomerAddressAndPhone,
      showPreviousCustomerDebt: _showPreviousCustomerDebt,
      printProductNameOnSeparateLine: _printProductNameOnSeparateLine,
      showExpiryDateOnA4: _showExpiryDateOnA4,
      showProductNumberOnA4: _showProductNumberOnA4,
      showProductDescription: _showProductDescription,
      useA4WhenSharingInvoice: _useA4WhenSharingInvoice,
      printImmediatelyAfterSave: _printImmediatelyAfterSave,
      showTaxQrOnInvoice: _showTaxQrOnInvoice,
      showProductImageOnInvoice: _showProductImageOnInvoice,
      labels: _labels,
    );
  }

  Future<void> _editInvoiceLabels() async {
    final controllers = <String, TextEditingController>{
      'invoiceTitle': TextEditingController(text: _labels.invoiceTitle),
      'invoiceNumber': TextEditingController(text: _labels.invoiceNumber),
      'date': TextEditingController(text: _labels.date),
      'client': TextEditingController(text: _labels.client),
      'total': TextEditingController(text: _labels.total),
      'paid': TextEditingController(text: _labels.paid),
      'balance': TextEditingController(text: _labels.balance),
      'previousBalance':
          TextEditingController(text: _labels.previousBalance),
      'product': TextEditingController(text: _labels.product),
      'quantity': TextEditingController(text: _labels.quantity),
      'price': TextEditingController(text: _labels.price),
      'lineTotal': TextEditingController(text: _labels.lineTotal),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xffead1ac),
          title: Text('تعديل مسميات الفاتورة',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360.h,
            child: SingleChildScrollView(
              child: Column(
                children: controllers.entries.map((e) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: e.key,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      setState(() {
        _labels = InvoiceLabels(
          invoiceTitle: controllers['invoiceTitle']!.text.trim(),
          invoiceNumber: controllers['invoiceNumber']!.text.trim(),
          date: controllers['date']!.text.trim(),
          client: controllers['client']!.text.trim(),
          total: controllers['total']!.text.trim(),
          paid: controllers['paid']!.text.trim(),
          balance: controllers['balance']!.text.trim(),
          previousBalance: controllers['previousBalance']!.text.trim(),
          product: controllers['product']!.text.trim(),
          quantity: controllers['quantity']!.text.trim(),
          price: controllers['price']!.text.trim(),
          lineTotal: controllers['lineTotal']!.text.trim(),
          address: _labels.address,
          phone: _labels.phone,
          description: _labels.description,
          productNumber: _labels.productNumber,
          expiryDate: _labels.expiryDate,
        );
      });
    }

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final settings = _currentSettings();
    await PrinterSettingsService.save(settings);

    if (_connectionType == PrinterConnectionType.bluetooth &&
        settings.bluetoothMacAddress.isNotEmpty) {
      final connected =
          await BluetoothPrinterService.connect(settings.bluetoothMacAddress);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(connected
            ? 'تم الحفظ والاتصال بالطابعة'
            : 'تم الحفظ لكن فشل الاتصال بالطابعة'),
      ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات')),
      );
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _searchBluetoothDevices() async {
    setState(() => _searching = true);

    final hasPermission = await BluetoothPrinterService.ensurePermissions();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يرجى منح صلاحية البلوتوث من إعدادات التطبيق')),
        );
      }
      return;
    }

    final bluetoothOn = await BluetoothPrinterService.isBluetoothOn();
    if (!bluetoothOn) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى تفعيل البلوتوث أولاً')),
        );
      }
      return;
    }

    try {
      final devices = await BluetoothPrinterService.getPairedDevices();
      if (!mounted) return;
      setState(() => _searching = false);

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'لا توجد أجهزة مقترنة. اربط الطابعة من إعدادات البلوتوث في الهاتف ثم أعد البحث'),
          ),
        );
        return;
      }

      final selected = await showDialog<PairedBluetoothDevice>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xffead1ac),
          title: Text(
            'اختر الطابعة',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18.sp,
              color: Colors.black.withOpacity(0.8),
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(
                    device.name,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 15.sp),
                  ),
                  subtitle: Text(
                    device.macAddress,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.sp),
                  ),
                  onTap: () => Navigator.pop(ctx, device),
                );
              },
            ),
          ),
        ),
      );

      if (selected != null && mounted) {
        await _connectToSelectedPrinter(selected);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء البحث: $e')),
        );
      }
    }
  }

  Future<void> _connectToSelectedPrinter(PairedBluetoothDevice selected) async {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xffead1ac),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.orange),
              SizedBox(height: 16.h),
              Text(
                'جاري الاتصال بالطابعة...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8.h),
              Text(
                selected.name,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );

    var connected = false;
    try {
      connected = await BluetoothPrinterService.connect(selected.macAddress);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Printer connect crashed: $e\n$st');
      }
      connected = false;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    setState(() {
      _macController.text = selected.macAddress;
      _deviceName = selected.name;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: connected ? 3 : 10),
      content: Text(connected
          ? 'تم الاتصال بـ ${selected.name}'
          : 'تعذر الاتصال بـ ${selected.name}\n'
              '• شغّل الطابعة وضع ورق الإيصال\n'
              '• تأكد أنها غير متصلة بهاتف آخر\n'
              '• من إعدادات البلوتوث: اضغط على الطابعة ثم «نسيان» واربطها من جديد\n'
              'MAC: ${selected.macAddress}'),
    ));
  }

  Future<void> _testPrint() async {
    final settings = _currentSettings();
    if (settings.bluetoothMacAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر طابعة بلوتوث أولاً')),
      );
      return;
    }
    final ok = await BluetoothPrinterService.printTestReceipt(settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'تمت طباعة الاختبار' : 'فشلت طباعة الاختبار'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade200,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.7),
          title: Text(
            'إعدادات الطابعة',
            style: TextStyle(color: Colors.white, fontSize: 18.sp),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (_connectionType == PrinterConnectionType.bluetooth)
              IconButton(
                icon: const Icon(Icons.print, color: Colors.white),
                tooltip: 'طباعة اختبار',
                onPressed: _loading ? null : _testPrint,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('رأس الإيصال (اسم المحل)'),
                    TextField(
                      controller: _storeNameController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'اسم المحل',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _storeAddressController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'العنوان (اختياري)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _storePhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'رقم الهاتف (اختياري)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),
                    _sectionLabel('نص أسفل فواتير المبيعات'),
                    _multilineField(_salesFooterController, minLines: 2),
                    SizedBox(height: 10.h),
                    _sectionLabel('نص أسفل تقارير A4'),
                    _multilineField(_a4FooterController, minLines: 2),
                    SizedBox(height: 10.h),
                    _sectionLabel('موقع النص الارتفاع'),
                    _numberField(_textHeightController),
                    SizedBox(height: 14.h),
                    _sectionLabel('نوع الطابعه'),
                    _connectionTypeRadios(),
                    if (_connectionType == PrinterConnectionType.bluetooth) ...[
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _macController,
                              readOnly: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                hintText: 'عنوان MAC للطابعة',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6.r),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10.w, vertical: 12.h),
                              ),
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          SizedBox(
                            height: 48.h,
                            child: ElevatedButton(
                              onPressed:
                                  _searching ? null : _searchBluetoothDevices,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade400,
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6.r),
                                ),
                              ),
                              child: _searching
                                  ? SizedBox(
                                      width: 20.w,
                                      height: 20.h,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text('بحث',
                                      style: TextStyle(fontSize: 15.sp)),
                            ),
                          ),
                        ],
                      ),
                      if (_deviceName.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 6.h),
                          child: Text(
                            'الجهاز: $_deviceName',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                    ],
                    SizedBox(height: 14.h),
                    _sectionLabel('حجم ورق الطابعه الحراريه'),
                    _paperSizeRadios(),
                    SizedBox(height: 14.h),
                    _dropdown(
                      label: 'عدد نسخ الفاتورة',
                      value: _invoiceCopies,
                      items: List.generate(5, (i) => i + 1),
                      onChanged: (v) => setState(() => _invoiceCopies = v!),
                    ),
                    _dropdown(
                      label: 'موديل الطابعة الحرارية',
                      value: _thermalPrinterModel,
                      items: List.generate(5, (i) => i + 1),
                      onChanged: (v) =>
                          setState(() => _thermalPrinterModel = v!),
                    ),
                    _dropdown(
                      label: 'موديل طابعة الباركود',
                      value: _barcodePrinterModel,
                      items: List.generate(5, (i) => i + 1),
                      onChanged: (v) =>
                          setState(() => _barcodePrinterModel = v!),
                    ),
                    _dropdown(
                      label: 'أمر قص الورق',
                      value: _paperCutCommand,
                      items: List.generate(3, (i) => i),
                      onChanged: (v) => setState(() => _paperCutCommand = v!),
                    ),
                    _dropdown(
                      label: 'أمر فتح الدرج',
                      value: _drawerOpenCommand,
                      items: List.generate(3, (i) => i),
                      onChanged: (v) =>
                          setState(() => _drawerOpenCommand = v!),
                    ),
                    SizedBox(height: 14.h),
                    _sectionLabel('حجم الخط'),
                    _numberField(_fontSizeController),
                    SizedBox(height: 10.h),
                    _sectionLabel('الهامش الايمن'),
                    _numberField(_rightMarginController),
                    SizedBox(height: 10.h),
                    _sectionLabel('الهامش الاسفل'),
                    _numberField(_bottomMarginController),
                    SizedBox(height: 14.h),
                    _switchTile(
                      'اظهار عنوان العميل ورقم تليفونه في الفاتورة',
                      _showCustomerAddressAndPhone,
                      (v) => setState(() => _showCustomerAddressAndPhone = v),
                    ),
                    _switchTile(
                      'اظهار مديونية العميل السابقه في الفاتورة',
                      _showPreviousCustomerDebt,
                      (v) => setState(() => _showPreviousCustomerDebt = v),
                    ),
                    _switchTile(
                      'طباعه اسم المنتج في صف مستقل',
                      _printProductNameOnSeparateLine,
                      (v) =>
                          setState(() => _printProductNameOnSeparateLine = v),
                    ),
                    _switchTile(
                      'عرض تاريخ الانتهاء في فاتورة المبيعات A4',
                      _showExpiryDateOnA4,
                      (v) => setState(() => _showExpiryDateOnA4 = v),
                    ),
                    _switchTile(
                      'عرض رقم المنتج في فاتورة المبيعات A4',
                      _showProductNumberOnA4,
                      (v) => setState(() => _showProductNumberOnA4 = v),
                    ),
                    _switchTile(
                      'اظهار وصف المنتج في الفاتورة',
                      _showProductDescription,
                      (v) => setState(() => _showProductDescription = v),
                    ),
                    _switchTile(
                      'اختيار قياس A4 عند ارسال فاتورة البيع',
                      _useA4WhenSharingInvoice,
                      (v) => setState(() => _useA4WhenSharingInvoice = v),
                    ),
                    _switchTile(
                      'طباعة الفاتورة مباشرة بعد الحفظ',
                      _printImmediatelyAfterSave,
                      (v) => setState(() => _printImmediatelyAfterSave = v),
                    ),
                    _switchTile(
                      'اظهار QR الضريبه في فاتوره البيع',
                      _showTaxQrOnInvoice,
                      (v) => setState(() => _showTaxQrOnInvoice = v),
                    ),
                    _switchTile(
                      'اظهار صورة المنتج في فاتورة البيع',
                      _showProductImageOnInvoice,
                      (v) => setState(() => _showProductImageOnInvoice = v),
                    ),
                    SizedBox(height: 10.h),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: ListTile(
                        title: Text(
                          'تعديل مسميات الفاتورة',
                          style: TextStyle(fontSize: 14.sp),
                        ),
                        trailing: ElevatedButton(
                          onPressed: _editInvoiceLabels,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade400,
                            foregroundColor: Colors.black87,
                          ),
                          child: Text('تعديل', style: TextStyle(fontSize: 14.sp)),
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade500,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6.r),
                          ),
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
                            : Text('حفظ',
                                style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
          color: Colors.black.withOpacity(0.75),
        ),
      ),
    );
  }

  Widget _multilineField(TextEditingController controller,
      {int minLines = 2}) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: 4,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6.r),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      ),
      style: TextStyle(fontSize: 14.sp),
    );
  }

  Widget _numberField(TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6.r),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
      ),
      style: TextStyle(fontSize: 14.sp),
    );
  }

  Widget _connectionTypeRadios() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Column(
        children: [
          _radioTile('PDF (A4)', PrinterConnectionType.pdf),
          _radioTile('Bluetooth (58/80mm)', PrinterConnectionType.bluetooth),
          _radioTile('WIFI (58/80mm)', PrinterConnectionType.wifi),
          _radioTile('USB (58/80mm)', PrinterConnectionType.usb),
        ],
      ),
    );
  }

  Widget _radioTile(String label, PrinterConnectionType type) {
    return RadioListTile<PrinterConnectionType>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(fontSize: 14.sp)),
      value: type,
      groupValue: _connectionType,
      activeColor: Colors.black54,
      onChanged: (v) => setState(() => _connectionType = v!),
    );
  }

  Widget _paperSizeRadios() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: RadioListTile<ThermalPaperSize>(
              dense: true,
              title: Text('80mm', style: TextStyle(fontSize: 14.sp)),
              value: ThermalPaperSize.mm80,
              groupValue: _paperSize,
              activeColor: Colors.black54,
              onChanged: (v) => setState(() => _paperSize = v!),
            ),
          ),
          Expanded(
            child: RadioListTile<ThermalPaperSize>(
              dense: true,
              title: Text('58mm', style: TextStyle(fontSize: 14.sp)),
              value: ThermalPaperSize.mm58,
              groupValue: _paperSize,
              activeColor: Colors.black54,
              onChanged: (v) => setState(() => _paperSize = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: SwitchListTile(
        title: Text(title, style: TextStyle(fontSize: 13.sp)),
        value: value,
        activeColor: Colors.orange,
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 14.sp, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: value,
                  items: items
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text('$e', style: TextStyle(fontSize: 14.sp)),
                          ))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
