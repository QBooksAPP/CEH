import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String canonicalAccountsDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String displayAccountsDate(String canonical) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(canonical);
  if (match == null) return canonical;
  return '${match.group(3)}-${match.group(2)}-${match.group(1)}';
}

DateTime? parseCanonicalAccountsDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final date = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  return canonicalAccountsDate(date) == value ? date : null;
}

String formatNgn(num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${negative ? '−' : ''}₦$grouped.${parts.last}';
}

/// Formats database-backed Billing tax rates for people, without changing the
/// stored DECIMAL precision or the immutable transaction snapshot.
String formatBillingTaxRate(Object? value) {
  final rate = value is num ? value.toDouble() : double.tryParse('$value');
  return '${(rate ?? 0).toStringAsFixed(2)}%';
}

double? parseNgnInput(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final amount = double.tryParse(normalized);
  return amount != null && amount > 0 ? amount : null;
}

double? calculateExpenseLineTotal(String quantity, String price) {
  final qty = double.tryParse(quantity.trim());
  final unitPrice = parseNgnInput(price);
  if (qty == null || qty <= 0 || unitPrice == null) return null;
  return (qty * unitPrice * 100).round() / 100;
}

double sumExpenseLineTotals(Iterable<num?> totals) =>
    totals.fold(0, (sum, value) => sum + (value?.toDouble() ?? 0));

class NgnAmountInputFormatter extends TextInputFormatter {
  const NgnAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var raw =
        newValue.text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
    final dot = raw.indexOf('.');
    if (dot >= 0) {
      raw =
          '${raw.substring(0, dot)}.${raw.substring(dot + 1).replaceAll('.', '')}';
      if (raw.length - dot - 1 > 2) raw = raw.substring(0, dot + 3);
    }
    if (raw.isEmpty) return const TextEditingValue();
    final parts = raw.split('.');
    final integer = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped =
        integer.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final formatted = parts.length == 2 ? '$grouped.${parts.last}' : grouped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AccountsDatePickerField extends StatefulWidget {
  const AccountsDatePickerField({
    super.key,
    required this.onChanged,
    this.initialCanonicalDate,
    this.label = 'Date',
  });

  final ValueChanged<String> onChanged;
  final String? initialCanonicalDate;
  final String label;

  @override
  State<AccountsDatePickerField> createState() =>
      _AccountsDatePickerFieldState();
}

class _AccountsDatePickerFieldState extends State<AccountsDatePickerField> {
  late DateTime _selected;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _selected = parseCanonicalAccountsDate(widget.initialCanonicalDate ?? '') ??
        DateTime.now();
    _controller = TextEditingController(
        text: displayAccountsDate(canonicalAccountsDate(_selected)));
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onChanged(canonicalAccountsDate(_selected)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _selected = picked;
      _controller.text = displayAccountsDate(canonicalAccountsDate(picked));
    });
    widget.onChanged(canonicalAccountsDate(picked));
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        key: const ValueKey('accounts-date-picker'),
        controller: _controller,
        readOnly: true,
        onTap: _pick,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
      );
}
