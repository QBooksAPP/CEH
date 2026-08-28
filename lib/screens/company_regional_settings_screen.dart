import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/api_client.dart';
import '../core/ceh_date_formatters.dart';
import '../models/company_regional_settings.dart';
import '../models/session.dart';

class CompanyRegionalSettingsScreen extends StatefulWidget {
  const CompanyRegionalSettingsScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<CompanyRegionalSettingsScreen> createState() =>
      _CompanyRegionalSettingsScreenState();
}

class _CompanyRegionalSettingsScreenState
    extends State<CompanyRegionalSettingsScreen> {
  final _api = const CehApiClient();
  CompanyRegionalSettings? _settings;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _api.companyRegionalSettings(widget.session);
      if (!mounted) return;
      setState(() => _settings = settings);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  Future<void> _save() async {
    final value = _settings;
    if (value == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _api.updateCompanyRegionalSettings(
        widget.session,
        timeZone: value.timeZone,
        dateFormat: value.dateFormat,
        timeFormat: value.timeFormat,
        baseCurrency: value.baseCurrency,
      );
      CehRegionalFormats.use(saved);
      if (!mounted) return;
      setState(() => _settings = saved);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company settings saved.')));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.code)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _replace({
    String? timeZone,
    String? dateFormat,
    String? timeFormat,
    String? baseCurrency,
  }) {
    final old = _settings!;
    setState(() => _settings = CompanyRegionalSettings(
          companyId: old.companyId,
          companyCode: old.companyCode,
          companyName: old.companyName,
          timeZone: timeZone ?? old.timeZone,
          dateFormat: dateFormat ?? old.dateFormat,
          timeFormat: timeFormat ?? old.timeFormat,
          baseCurrency: baseCurrency ?? old.baseCurrency,
          baseCurrencyProtected: old.baseCurrencyProtected,
        ));
  }

  Future<void> _pickTimeZone() async {
    final search = TextEditingController();
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.text.trim().toLowerCase();
          final visible = zones
              .where((zone) => zone.toLowerCase().contains(query))
              .take(120)
              .toList();
          return AlertDialog(
            title: const Text('Select time zone'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(children: [
                TextField(
                  key: const Key('time-zone-search'),
                  controller: search,
                  autofocus: true,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search IANA time zones'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) => ListTile(
                      title: Text(visible[index]),
                      onTap: () => Navigator.pop(dialogContext, visible[index]),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    search.dispose();
    if (selected != null) _replace(timeZone: selected);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.user.isAdmin) {
      return const Scaffold(
          body: Center(child: Text('Admin access required.')));
    }
    final value = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Regional & Currency Settings')),
      body: value == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text('Settings unavailable: $_error'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(value.companyName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                    'Controls how dates, times and monetary values are displayed. Database and API dates remain canonical.'),
                const SizedBox(height: 24),
                ListTile(
                  key: const Key('company-time-zone'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4)),
                  title: const Text('Time zone'),
                  subtitle: Text(value.timeZone),
                  trailing: const Icon(Icons.search),
                  onTap: _pickTimeZone,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('company-date-format'),
                  initialValue: value.dateFormat,
                  decoration: const InputDecoration(labelText: 'Date format'),
                  items: const ['DD-MM-YYYY', 'MM-DD-YYYY', 'YYYY-MM-DD']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => v == null ? null : _replace(dateFormat: v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('company-time-format'),
                  initialValue: value.timeFormat,
                  decoration: const InputDecoration(labelText: 'Time format'),
                  items: const {
                    '24_HOUR': '24-hour',
                    '12_HOUR': '12-hour',
                  }
                      .entries
                      .map((v) =>
                          DropdownMenuItem(value: v.key, child: Text(v.value)))
                      .toList(),
                  onChanged: (v) => v == null ? null : _replace(timeFormat: v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('company-base-currency'),
                  initialValue: value.baseCurrency,
                  decoration: const InputDecoration(labelText: 'Base currency'),
                  items: const {
                    'NGN': 'NGN — Nigerian Naira',
                    'GBP': 'GBP — Pound Sterling',
                    'USD': 'USD — US Dollar',
                    'EUR': 'EUR — Euro',
                    'AED': 'AED — UAE Dirham',
                  }
                      .entries
                      .map((v) =>
                          DropdownMenuItem(value: v.key, child: Text(v.value)))
                      .toList(),
                  onChanged: value.baseCurrencyProtected
                      ? null
                      : (v) => v == null ? null : _replace(baseCurrency: v),
                ),
                if (value.baseCurrencyProtected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Base currency is locked because financial postings exist. A controlled migration is required to change it.',
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('save-company-regional-settings'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save settings'),
                ),
              ],
            ),
    );
  }
}
