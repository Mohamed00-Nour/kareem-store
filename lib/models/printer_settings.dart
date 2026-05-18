import 'invoice_labels.dart';

enum PrinterConnectionType { pdf, bluetooth, wifi, usb }

enum ThermalPaperSize { mm58, mm80 }

extension ThermalPaperSizeLayout on ThermalPaperSize {
  /// Typical character count per line on thermal printers.
  int get charsPerLine => this == ThermalPaperSize.mm58 ? 32 : 48;

  /// Print head width in dots at 203 DPI.
  int get printWidthDots => this == ThermalPaperSize.mm58 ? 384 : 576;

  int get widthMm => this == ThermalPaperSize.mm58 ? 58 : 80;
}

class PrinterSettings {
  final String salesInvoiceFooter;
  final String a4ReportFooter;
  final int textHeightPosition;
  final PrinterConnectionType connectionType;
  final String bluetoothMacAddress;
  final String bluetoothDeviceName;
  final ThermalPaperSize paperSize;
  final int invoiceCopies;
  final int thermalPrinterModel;
  final int barcodePrinterModel;
  final int paperCutCommand;
  final int drawerOpenCommand;
  final int fontSize;
  final int rightMargin;
  final int bottomMargin;
  final bool showCustomerAddressAndPhone;
  final bool showPreviousCustomerDebt;
  final bool printProductNameOnSeparateLine;
  final bool showExpiryDateOnA4;
  final bool showProductNumberOnA4;
  final bool showProductDescription;
  final bool useA4WhenSharingInvoice;
  final bool printImmediatelyAfterSave;
  final bool showTaxQrOnInvoice;
  final bool showProductImageOnInvoice;
  final InvoiceLabels labels;

  const PrinterSettings({
    this.salesInvoiceFooter = '',
    this.a4ReportFooter = '',
    this.textHeightPosition = 10,
    this.connectionType = PrinterConnectionType.bluetooth,
    this.bluetoothMacAddress = '',
    this.bluetoothDeviceName = '',
    this.paperSize = ThermalPaperSize.mm80,
    this.invoiceCopies = 1,
    this.thermalPrinterModel = 2,
    this.barcodePrinterModel = 1,
    this.paperCutCommand = 1,
    this.drawerOpenCommand = 1,
    this.fontSize = 20,
    this.rightMargin = 0,
    this.bottomMargin = 0,
    this.showCustomerAddressAndPhone = false,
    this.showPreviousCustomerDebt = false,
    this.printProductNameOnSeparateLine = false,
    this.showExpiryDateOnA4 = false,
    this.showProductNumberOnA4 = false,
    this.showProductDescription = false,
    this.useA4WhenSharingInvoice = false,
    this.printImmediatelyAfterSave = false,
    this.showTaxQrOnInvoice = false,
    this.showProductImageOnInvoice = false,
    this.labels = const InvoiceLabels(),
  });

  PrinterSettings copyWith({
    String? salesInvoiceFooter,
    String? a4ReportFooter,
    int? textHeightPosition,
    PrinterConnectionType? connectionType,
    String? bluetoothMacAddress,
    String? bluetoothDeviceName,
    ThermalPaperSize? paperSize,
    int? invoiceCopies,
    int? thermalPrinterModel,
    int? barcodePrinterModel,
    int? paperCutCommand,
    int? drawerOpenCommand,
    int? fontSize,
    int? rightMargin,
    int? bottomMargin,
    bool? showCustomerAddressAndPhone,
    bool? showPreviousCustomerDebt,
    bool? printProductNameOnSeparateLine,
    bool? showExpiryDateOnA4,
    bool? showProductNumberOnA4,
    bool? showProductDescription,
    bool? useA4WhenSharingInvoice,
    bool? printImmediatelyAfterSave,
    bool? showTaxQrOnInvoice,
    bool? showProductImageOnInvoice,
    InvoiceLabels? labels,
  }) {
    return PrinterSettings(
      salesInvoiceFooter: salesInvoiceFooter ?? this.salesInvoiceFooter,
      a4ReportFooter: a4ReportFooter ?? this.a4ReportFooter,
      textHeightPosition: textHeightPosition ?? this.textHeightPosition,
      connectionType: connectionType ?? this.connectionType,
      bluetoothMacAddress: bluetoothMacAddress ?? this.bluetoothMacAddress,
      bluetoothDeviceName: bluetoothDeviceName ?? this.bluetoothDeviceName,
      paperSize: paperSize ?? this.paperSize,
      invoiceCopies: invoiceCopies ?? this.invoiceCopies,
      thermalPrinterModel: thermalPrinterModel ?? this.thermalPrinterModel,
      barcodePrinterModel: barcodePrinterModel ?? this.barcodePrinterModel,
      paperCutCommand: paperCutCommand ?? this.paperCutCommand,
      drawerOpenCommand: drawerOpenCommand ?? this.drawerOpenCommand,
      fontSize: fontSize ?? this.fontSize,
      rightMargin: rightMargin ?? this.rightMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      showCustomerAddressAndPhone:
          showCustomerAddressAndPhone ?? this.showCustomerAddressAndPhone,
      showPreviousCustomerDebt:
          showPreviousCustomerDebt ?? this.showPreviousCustomerDebt,
      printProductNameOnSeparateLine:
          printProductNameOnSeparateLine ?? this.printProductNameOnSeparateLine,
      showExpiryDateOnA4: showExpiryDateOnA4 ?? this.showExpiryDateOnA4,
      showProductNumberOnA4:
          showProductNumberOnA4 ?? this.showProductNumberOnA4,
      showProductDescription:
          showProductDescription ?? this.showProductDescription,
      useA4WhenSharingInvoice:
          useA4WhenSharingInvoice ?? this.useA4WhenSharingInvoice,
      printImmediatelyAfterSave:
          printImmediatelyAfterSave ?? this.printImmediatelyAfterSave,
      showTaxQrOnInvoice: showTaxQrOnInvoice ?? this.showTaxQrOnInvoice,
      showProductImageOnInvoice:
          showProductImageOnInvoice ?? this.showProductImageOnInvoice,
      labels: labels ?? this.labels,
    );
  }

  Map<String, dynamic> toMap() => {
        'salesInvoiceFooter': salesInvoiceFooter,
        'a4ReportFooter': a4ReportFooter,
        'textHeightPosition': textHeightPosition,
        'connectionType': connectionType.index,
        'bluetoothMacAddress': bluetoothMacAddress,
        'bluetoothDeviceName': bluetoothDeviceName,
        'paperSize': paperSize.index,
        'invoiceCopies': invoiceCopies,
        'thermalPrinterModel': thermalPrinterModel,
        'barcodePrinterModel': barcodePrinterModel,
        'paperCutCommand': paperCutCommand,
        'drawerOpenCommand': drawerOpenCommand,
        'fontSize': fontSize,
        'rightMargin': rightMargin,
        'bottomMargin': bottomMargin,
        'showCustomerAddressAndPhone': showCustomerAddressAndPhone,
        'showPreviousCustomerDebt': showPreviousCustomerDebt,
        'printProductNameOnSeparateLine': printProductNameOnSeparateLine,
        'showExpiryDateOnA4': showExpiryDateOnA4,
        'showProductNumberOnA4': showProductNumberOnA4,
        'showProductDescription': showProductDescription,
        'useA4WhenSharingInvoice': useA4WhenSharingInvoice,
        'printImmediatelyAfterSave': printImmediatelyAfterSave,
        'showTaxQrOnInvoice': showTaxQrOnInvoice,
        'showProductImageOnInvoice': showProductImageOnInvoice,
        'labels': labels.toMap(),
      };

  factory PrinterSettings.fromMap(Map<String, dynamic> map) {
    return PrinterSettings(
      salesInvoiceFooter: map['salesInvoiceFooter'] as String? ?? '',
      a4ReportFooter: map['a4ReportFooter'] as String? ?? '',
      textHeightPosition: map['textHeightPosition'] as int? ?? 10,
      connectionType: PrinterConnectionType.values[
          (map['connectionType'] as int?)?.clamp(0, 3) ?? 1],
      bluetoothMacAddress: map['bluetoothMacAddress'] as String? ?? '',
      bluetoothDeviceName: map['bluetoothDeviceName'] as String? ?? '',
      paperSize: ThermalPaperSize
          .values[(map['paperSize'] as int?)?.clamp(0, 1) ?? 1],
      invoiceCopies: map['invoiceCopies'] as int? ?? 1,
      thermalPrinterModel: map['thermalPrinterModel'] as int? ?? 2,
      barcodePrinterModel: map['barcodePrinterModel'] as int? ?? 1,
      paperCutCommand: map['paperCutCommand'] as int? ?? 1,
      drawerOpenCommand: map['drawerOpenCommand'] as int? ?? 1,
      fontSize: map['fontSize'] as int? ?? 20,
      rightMargin: map['rightMargin'] as int? ?? 0,
      bottomMargin: map['bottomMargin'] as int? ?? 0,
      showCustomerAddressAndPhone:
          map['showCustomerAddressAndPhone'] as bool? ?? false,
      showPreviousCustomerDebt:
          map['showPreviousCustomerDebt'] as bool? ?? false,
      printProductNameOnSeparateLine:
          map['printProductNameOnSeparateLine'] as bool? ?? false,
      showExpiryDateOnA4: map['showExpiryDateOnA4'] as bool? ?? false,
      showProductNumberOnA4: map['showProductNumberOnA4'] as bool? ?? false,
      showProductDescription: map['showProductDescription'] as bool? ?? false,
      useA4WhenSharingInvoice: map['useA4WhenSharingInvoice'] as bool? ?? false,
      printImmediatelyAfterSave:
          map['printImmediatelyAfterSave'] as bool? ?? false,
      showTaxQrOnInvoice: map['showTaxQrOnInvoice'] as bool? ?? false,
      showProductImageOnInvoice:
          map['showProductImageOnInvoice'] as bool? ?? false,
      labels: InvoiceLabels.fromMap(
          map['labels'] as Map<String, dynamic>?),
    );
  }
}
