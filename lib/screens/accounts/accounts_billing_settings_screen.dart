import 'package:flutter/material.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class AccountsBillingSettingsScreen extends StatefulWidget {
  const AccountsBillingSettingsScreen(
      {super.key, required this.session, required this.api});
  final CehSession session;
  final CehApiClient api;

  @override
  State<AccountsBillingSettingsScreen> createState() =>
      _AccountsBillingSettingsScreenState();
}

class _AccountsBillingSettingsScreenState
    extends State<AccountsBillingSettingsScreen> {
  Map<String, dynamic>? _configuration;
  bool _busy = false;
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  final _tin = TextEditingController();
  final _bankDetails = TextEditingController();
  final _termsText = TextEditingController(text: 'Advance Payment');
  String _defaultTerms = 'ADVANCE_PAYMENT';

  @override
  void initState() {
    super.initState();
    if (widget.session.user.isAdmin) _load();
  }

  Future<void> _load() async {
    final data = await widget.api.taxConfiguration(widget.session);
    if (!mounted) return;
    final settings =
        Map<String, dynamic>.from(data['invoice_settings'] as Map? ?? const {});
    setState(() {
      _configuration = data;
      _legalName.text = '${settings['company_legal_name'] ?? ''}';
      _address.text = '${settings['company_address'] ?? ''}';
      _tin.text = '${settings['tax_identifier'] ?? ''}';
      _bankDetails.text = '${settings['payment_bank_details'] ?? ''}';
      _termsText.text =
          '${settings['default_terms_text'] ?? 'Advance Payment'}';
      _defaultTerms = '${settings['default_terms'] ?? 'ADVANCE_PAYMENT'}';
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _legalName,
      _address,
      _tin,
      _bankDetails,
      _termsText
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setActive(Map<String, dynamic> code, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Deactivate tax code?'),
                content: Text(
                    '${code['code']} will no longer be offered for new transactions. Historical invoices and receipts remain unchanged.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep Active')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Deactivate'))
                ],
              ));
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.setTaxCodeActive(
          widget.session, (code['id'] as num).toInt(), active);
      await _load();
    } on ApiException catch (e) {
      _message(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTaxCode() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final rate = TextEditingController();
    var type = 'VAT';
    var base = 'NET';
    var active = true;
    var from = canonicalAccountsDate(DateTime.now());
    String? to;
    final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setModal) {
              Future<void> pick(bool start) async {
                final current =
                    parseCanonicalAccountsDate(start ? from : to ?? '') ??
                        DateTime.now();
                final selected = await showDatePicker(
                    context: context,
                    initialDate: current,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (selected != null) {
                  setModal(() {
                    if (start) {
                      from = canonicalAccountsDate(selected);
                    } else {
                      to = canonicalAccountsDate(selected);
                    }
                  });
                }
              }

              return AlertDialog(
                  title: const Text('Add Tax Code'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration:
                            const InputDecoration(labelText: 'Tax Type'),
                        items: const [
                          DropdownMenuItem(value: 'VAT', child: Text('VAT')),
                          DropdownMenuItem(value: 'WHT', child: Text('WHT'))
                        ],
                        onChanged: (value) => setModal(() {
                              type = value!;
                              base = type == 'VAT' ? 'NET' : 'GROSS';
                            })),
                    TextField(
                        key: const ValueKey('tax-code'),
                        controller: code,
                        decoration: const InputDecoration(labelText: 'Code')),
                    TextField(
                        key: const ValueKey('tax-name'),
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Name')),
                    TextField(
                        key: const ValueKey('tax-rate'),
                        controller: rate,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'Rate %')),
                    if (type == 'WHT')
                      DropdownButtonFormField<String>(
                          initialValue: base,
                          decoration: const InputDecoration(
                              labelText: 'Calculation Base'),
                          items: const [
                            DropdownMenuItem(
                                value: 'GROSS', child: Text('Gross')),
                            DropdownMenuItem(value: 'NET', child: Text('Net')),
                            DropdownMenuItem(
                                value: 'MANUAL', child: Text('Manual'))
                          ],
                          onChanged: (value) => setModal(() => base = value!)),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Effective From'),
                        subtitle: Text(displayAccountsDate(from)),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: () => pick(true)),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Effective To — optional'),
                        subtitle: Text(to == null
                            ? 'No end date'
                            : displayAccountsDate(to!)),
                        trailing: to == null
                            ? const Icon(Icons.calendar_today_outlined)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setModal(() => to = null)),
                        onTap: () => pick(false)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        value: active,
                        onChanged: (value) => setModal(() => active = value)),
                    const Text(
                        'VAT maps to Output VAT Payable. WHT maps to WHT Receivable. Existing historical snapshots are never rewritten.')
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          if (code.text.trim().isEmpty ||
                              name.text.trim().isEmpty ||
                              double.tryParse(rate.text.trim()) == null) {
                            return;
                          }
                          Navigator.pop(context, {
                            'tax_type': type,
                            'code': code.text.trim(),
                            'name': name.text.trim(),
                            'rate_percent': rate.text.trim(),
                            'calculation_base': base,
                            'effective_from': from,
                            'effective_to': to,
                            'is_active': active
                          });
                        },
                        child: const Text('Add Tax Code'))
                  ]);
            }));
    code.dispose();
    name.dispose();
    rate.dispose();
    if (payload == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.createTaxCode(widget.session, payload);
      await _load();
    } on ApiException catch (e) {
      _message(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveInvoiceSettings() async {
    setState(() => _busy = true);
    try {
      await widget.api.updateInvoiceSettings(widget.session, {
        'company_legal_name': _legalName.text.trim(),
        'company_address': _address.text.trim(),
        'tax_identifier': _tin.text.trim(),
        'payment_bank_details': _bankDetails.text.trim(),
        'default_terms': _defaultTerms,
        'default_terms_text': _termsText.text.trim()
      });
      _message('Invoice settings saved.');
      await _load();
    } on ApiException catch (e) {
      _message(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.user.isAdmin) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    final codes = (_configuration?['tax_codes'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Billing Settings')),
        body: _configuration == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(18), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(
                      child: AccountsSectionTitle('Tax Configuration',
                          subtitle:
                              'Effective-dated VAT and WHT settings. Rates already snapshotted on transactions remain unchanged.')),
                  FilledButton.icon(
                      key: const ValueKey('add-tax-code'),
                      onPressed: _busy ? null : _addTaxCode,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Tax Code'))
                ]),
                for (final code in codes)
                  Card(
                      child: SwitchListTile(
                          title: Text('${code['code']} • ${code['name']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${code['tax_type']} • ${code['rate_percent']}%${code['tax_type'] == 'WHT' ? ' • ${code['calculation_base']}' : ''}\n${displayAccountsDate('${code['effective_from']}')} → ${code['effective_to'] == null ? 'No end date' : displayAccountsDate('${code['effective_to']}')}'),
                          value: '${code['is_active']}' == '1' ||
                              code['is_active'] == true,
                          onChanged: _busy
                              ? null
                              : (value) => _setActive(code, value))),
                const SizedBox(height: 24),
                const AccountsSectionTitle('Invoice Settings',
                    subtitle:
                        'Used on invoice PDFs. Leave unknown company details blank rather than inventing them.'),
                TextField(
                    controller: _legalName,
                    decoration:
                        const InputDecoration(labelText: 'Company Legal Name')),
                TextField(
                    controller: _address,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Company Address')),
                TextField(
                    controller: _tin,
                    decoration: const InputDecoration(
                        labelText: 'Tax Identifier / TIN')),
                TextField(
                    controller: _bankDetails,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Payment Bank Details')),
                DropdownButtonFormField<String>(
                    initialValue: _defaultTerms,
                    decoration:
                        const InputDecoration(labelText: 'Default Terms'),
                    items: const [
                      DropdownMenuItem(
                          value: 'ADVANCE_PAYMENT',
                          child: Text('Advance Payment')),
                      DropdownMenuItem(
                          value: 'DUE_ON_ISSUE', child: Text('Due on Issue')),
                      DropdownMenuItem(
                          value: 'NET_DAYS', child: Text('Net Days')),
                      DropdownMenuItem(
                          value: 'FIXED_DUE_DATE',
                          child: Text('Fixed Due Date')),
                      DropdownMenuItem(value: 'CUSTOM', child: Text('Custom'))
                    ],
                    onChanged: (value) =>
                        setState(() => _defaultTerms = value!)),
                TextField(
                    controller: _termsText,
                    decoration:
                        const InputDecoration(labelText: 'Default Terms Text')),
                const SizedBox(height: 16),
                Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                        key: const ValueKey('save-invoice-settings'),
                        onPressed: _busy ? null : _saveInvoiceSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Invoice Settings')))
              ]));
  }
}
