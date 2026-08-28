import 'package:ceh/core/accounts_formatters.dart';
import 'package:ceh/models/company_regional_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  const ceh = CompanyRegionalSettings();
  const uk =
      CompanyRegionalSettings(timeZone: 'Europe/London', baseCurrency: 'GBP');
  const us = CompanyRegionalSettings(
      timeZone: 'America/New_York',
      dateFormat: 'MM-DD-YYYY',
      timeFormat: '12_HOUR',
      baseCurrency: 'USD');

  test('CEH compatibility defaults remain Lagos DD-MM 24-hour NGN', () {
    expect(ceh.timeZone, 'Africa/Lagos');
    expect(displayCehDate('2026-08-28', settings: ceh), '28-08-2026');
    expect(displayCehDateTime('2026-08-28T13:30:00Z', settings: ceh),
        '28-08-2026 14:30');
    expect(formatCurrency(1234.5, currencyCode: ceh.baseCurrency), '₦1,234.50');
  });

  test('UK timezone honours winter and summer DST', () {
    expect(displayCehDateTime('2026-01-15T12:00:00Z', settings: uk),
        '15-01-2026 12:00');
    expect(displayCehDateTime('2026-07-15T12:00:00Z', settings: uk),
        '15-07-2026 13:00');
    expect(formatCurrency(99, currencyCode: 'GBP'), '£99.00');
  });

  test('US timezone honours DST and 12-hour display', () {
    expect(displayCehDateTime('2026-01-15T17:30:00Z', settings: us),
        '01-15-2026 12:30 PM');
    expect(displayCehDateTime('2026-07-15T16:30:00Z', settings: us),
        '07-15-2026 12:30 PM');
    expect(formatCurrency(99, currencyCode: 'USD'), r'$99.00');
  });

  test('date-only values never timezone shift and API stays canonical', () {
    expect(displayCehDate('2026-01-01', settings: us), '01-01-2026');
    expect(canonicalCehDate(DateTime(2026, 1, 1)), '2026-01-01');
  });

  test('EUR and AED metadata format without changing values', () {
    expect(formatCurrency(1234.56, currencyCode: 'EUR'), '€1,234.56');
    expect(formatCurrency(1234.56, currencyCode: 'AED'), 'AED 1,234.56');
  });

  test('legacy NGN aliases use current company settings centrally', () {
    CehRegionalFormats.use(uk);
    expect(formatNgn(12), '£12.00');
    CehRegionalFormats.use(ceh);
  });
}
