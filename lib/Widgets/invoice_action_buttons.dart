import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Print / share / edit / delete icon row (matches client invoices page).
class InvoiceActionButtons extends StatelessWidget {
  final VoidCallback? onPrint;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showEditDelete;

  const InvoiceActionButtons({
    super.key,
    this.onPrint,
    this.onShare,
    this.onEdit,
    this.onDelete,
    this.showEditDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onPrint != null)
          IconButton(
            icon: const Icon(Icons.print_outlined, color: Colors.black87),
            tooltip: 'طباعة',
            onPressed: onPrint,
          ),
        if (onShare != null)
          IconButton(
            icon: FaIcon(
              FontAwesomeIcons.whatsapp,
              color: Colors.green.shade700,
              size: 22,
            ),
            tooltip: 'مشاركة في واتساب',
            onPressed: onShare,
          ),
        if (showEditDelete && onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            tooltip: 'تعديل',
            onPressed: onEdit,
          ),
        if (showEditDelete && onDelete != null)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'حذف',
            onPressed: onDelete,
          ),
      ],
    );
  }
}
