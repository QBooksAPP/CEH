import 'package:timezone/timezone.dart' as tz;

import '../models/company_regional_settings.dart';

class CehRegionalFormats {
  CehRegionalFormats._();
  static CompanyRegionalSettings current = const CompanyRegionalSettings();
  static void use(CompanyRegionalSettings settings) => current = settings;
}

final _canonicalDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _dateTime =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?');

String canonicalCehDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

DateTime? parseCanonicalCehDate(String? value) {
  final match = _canonicalDate.firstMatch((value ?? '').trim());
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

String _dateParts(int year, int month, int day, String format) {
  final y = year.toString().padLeft(4, '0');
  final m = month.toString().padLeft(2, '0');
  final d = day.toString().padLeft(2, '0');
  return switch (format) {
    'MM-DD-YYYY' => '$m-$d-$y',
    'YYYY-MM-DD' => '$y-$m-$d',
    'DD/MM/YYYY' => '$d/$m/$y',
    'MM/DD/YYYY' => '$m/$d/$y',
    _ => '$d-$m-$y',
  };
}

String displayCehDate(String? value, {CompanyRegionalSettings? settings}) {
  final raw = (value ?? '').trim();
  final match = _canonicalDate.firstMatch(raw) ?? _dateTime.firstMatch(raw);
  if (match == null) return raw;
  return _dateParts(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      (settings ?? CehRegionalFormats.current).dateFormat);
}

String displayCehDateTime(String? value, {CompanyRegionalSettings? settings}) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return raw;
  final regional = settings ?? CehRegionalFormats.current;
  DateTime? local;
  final zoned = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
  if (zoned) {
    final instant = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (instant != null) {
      try {
        local = tz.TZDateTime.from(
            instant.toUtc(), tz.getLocation(regional.timeZone));
      } catch (_) {
        local = instant.toLocal();
      }
    }
  }
  if (local == null) {
    final match = _dateTime.firstMatch(raw);
    if (match == null) return displayCehDate(raw, settings: regional);
    local = DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.tryParse(match[6] ?? '') ?? 0,
    );
  }
  final date =
      _dateParts(local.year, local.month, local.day, regional.dateFormat);
  var hour = local.hour;
  var suffix = '';
  if (regional.timeFormat == '12_HOUR') {
    suffix = hour >= 12 ? ' PM' : ' AM';
    hour %= 12;
    if (hour == 0) hour = 12;
  }
  return '$date ${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}$suffix';
}
