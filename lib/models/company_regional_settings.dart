class CompanyRegionalSettings {
  const CompanyRegionalSettings({
    this.companyId = 1,
    this.companyCode = 'CEH',
    this.companyName = 'Concrete Equipment Hire Limited',
    this.timeZone = 'Africa/Lagos',
    this.dateFormat = 'DD-MM-YYYY',
    this.timeFormat = '24_HOUR',
    this.baseCurrency = 'NGN',
    this.baseCurrencyProtected = true,
  });

  final int companyId;
  final String companyCode;
  final String companyName;
  final String timeZone;
  final String dateFormat;
  final String timeFormat;
  final String baseCurrency;
  final bool baseCurrencyProtected;

  factory CompanyRegionalSettings.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return CompanyRegionalSettings(
      companyId: (value['company_id'] as num?)?.toInt() ?? 1,
      companyCode: '${value['company_code'] ?? 'CEH'}',
      companyName:
          '${value['company_name'] ?? 'Concrete Equipment Hire Limited'}',
      timeZone: '${value['time_zone'] ?? 'Africa/Lagos'}',
      dateFormat: '${value['date_format'] ?? 'DD-MM-YYYY'}',
      timeFormat: '${value['time_format'] ?? '24_HOUR'}',
      baseCurrency: '${value['base_currency'] ?? 'NGN'}',
      baseCurrencyProtected: value['base_currency_protected'] == null
          ? true
          : value['base_currency_protected'] == true ||
              value['base_currency_protected'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'company_code': companyCode,
        'company_name': companyName,
        'time_zone': timeZone,
        'date_format': dateFormat,
        'time_format': timeFormat,
        'base_currency': baseCurrency,
        'base_currency_protected': baseCurrencyProtected,
      };
}
