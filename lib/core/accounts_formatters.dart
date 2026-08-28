import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ceh_date_formatters.dart';

export 'ceh_date_formatters.dart';

String canonicalAccountsDate(DateTime date) => canonicalCehDate(date);

String displayAccountsDate(String canonical) {
  return displayCehDate(canonical);
}

String displayAccountsTimestampDate(String timestamp) {
  return displayCehDate(timestamp);
}

DateTime? parseCanonicalAccountsDate(String value) {
  return parseCanonicalCehDate(value);
}

String formatNgn(num value) {
  return formatCurrency(value);
}

const _currencySymbols = <String, String>{
  'NGN': '₦',
  'GBP': '£',
  'USD': r'$',
  'EUR': '€',
  'AED': 'AED',
};

String companyCurrencySymbol({String? currencyCode}) {
  final code = (currencyCode ?? CehRegionalFormats.current.baseCurrency)
      .trim()
      .toUpperCase();
  return _currencySymbols[code] ?? code;
}

String formatCurrency(num value, {String? currencyCode}) {
  final code = (currencyCode ?? CehRegionalFormats.current.baseCurrency)
      .trim()
      .toUpperCase();
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final symbol = companyCurrencySymbol(currencyCode: code);
  return '${negative ? '−' : ''}$symbol${symbol.length > 1 ? ' ' : ''}$grouped.${parts.last}';
}

/// Formats database-backed Billing tax rates for people, without changing the
/// stored DECIMAL precision or the immutable transaction snapshot.
String formatBillingTaxRate(Object? value) {
  final rate = value is num ? value.toDouble() : double.tryParse('$value');
  return '${(rate ?? 0).toStringAsFixed(2)}%';
}

int calculateTaxMinorUnits(int baseMinor, Object? rateValue) {
  if (baseMinor < 0) throw const FormatException('Negative tax base');
  final rate = '${rateValue ?? ''}'.trim();
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,6}))?$').firstMatch(rate);
  if (match == null) throw const FormatException('Invalid tax rate');
  final millionths =
      BigInt.from(int.parse(match.group(1)!)) * BigInt.from(1000000) +
          BigInt.from(int.parse((match.group(2) ?? '').padRight(6, '0')));
  final divisor = BigInt.from(100000000);
  final numerator = BigInt.from(baseMinor) * millionths;
  return ((numerator + divisor ~/ BigInt.two) ~/ divisor).toInt();
}

String formatAccountsStatus(String value) => value
    .trim()
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) =>
        '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
    .join(' ');

double? parseNgnInput(String value) {
  final normalized = normalizeNgnInput(value);
  if (normalized == null) return null;
  final amount = double.tryParse(normalized);
  return amount != null && amount > 0 ? amount : null;
}

/// Returns an API-safe decimal without presentation commas, or null when the
/// input is malformed. Financial APIs remain authoritative for validation.
String? normalizeNgnInput(String value, {bool allowZero = false}) {
  final presented = value.trim();
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$')
      .hasMatch(presented)) {
    return null;
  }
  final normalized = presented.replaceAll(',', '');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final minor = parseNgnMinorUnits(normalized);
  if (minor == null || (!allowZero && minor <= 0)) return null;
  return normalized;
}

/// Parses NGN input exactly into minor units without floating-point math.
int? parseNgnMinorUnits(String value, {bool allowZero = true}) {
  final presented = value.trim();
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$')
      .hasMatch(presented)) {
    return null;
  }
  final normalized = presented.replaceAll(',', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final minor = whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  return allowZero || minor > 0 ? minor : null;
}

String ngnMinorUnitsForApi(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

String completeNgnInput(String value) {
  final minor = parseNgnMinorUnits(value);
  if (minor == null) return value;
  final whole = (minor ~/ 100)
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '$whole.${(minor % 100).toString().padLeft(2, '0')}';
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
    final rawCursor =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final significantBeforeCursor = newValue.text
        .substring(0, rawCursor)
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .length;
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
    var seen = 0;
    var cursor = formatted.length;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'[0-9.]').hasMatch(formatted[i])) seen++;
      if (seen >= significantBeforeCursor) {
        cursor = i + 1;
        break;
      }
    }
    if (significantBeforeCursor == 0) cursor = 0;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
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
