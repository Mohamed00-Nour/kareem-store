import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Phone input with fixed Egypt country code [+20]; user types the rest.
class EgyptPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final bool autofocus;

  const EgyptPhoneField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.autofocus = false,
  });

  /// Digits only for WhatsApp (e.g. 201012345678).
  /// Stored WhatsApp digits (e.g. 201012345678) → local part for the input field.
  static String toLocalPartForInput(String storedDigits) {
    final digits = storedDigits.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('20') && digits.length > 2) {
      return digits.substring(2);
    }
    return digits;
  }

  static String toWhatsappDigits(String localPart) {
    var digits = localPart.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('20') && digits.length >= 12) {
      return digits;
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '20$digits';
  }

  static bool isValidLocalPart(String localPart) {
    final digits = localPart.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    final normalized = digits.startsWith('0') ? digits.substring(1) : digits;
    return normalized.length >= 9 && normalized.length <= 10;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\-]')),
        LengthLimitingTextInputFormatter(11),
      ],
      decoration: InputDecoration(
        labelText: labelText ?? 'رقم الهاتف',
        hintText: hintText ?? '1xxxxxxxxx',
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 12, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+20',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(width: 6),
              Text('|', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
