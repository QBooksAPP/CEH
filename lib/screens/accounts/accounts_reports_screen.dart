import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/accounts_formatters.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class AccountsReportsScreen extends StatelessWidget {
  const AccountsReportsScreen(
      {super.key, required this.session, this.api = const CehApiClient()});
  final CehSession session;
  final CehApiClient api;

  @override
  Widget build(BuildContext context) {
    const planned = [
      ('Expenses by Month', Icons.calendar_month_outlined),
      ('Expenses by Category', Icons.donut_large_outlined),
      ('Project Contribution', Icons.business_center_outlined),
      ('Equipment Contribution', Icons.precision_manufacturing_outlined),
      ('Supplier Spend', Icons.local_shipping_outlined),
      ('Billing Status', Icons.receipt_long_outlined),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const AccountsSectionTitle('Live reports',
            subtitle:
                'Authoritative read-only Accounts reporting and audit exports'),
        AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: 2.25,
            children: [
              AccountsMenuCard(
                  title: 'Petty Cash Report',
                  subtitle: 'Custodian activity, allocations and evidence pack',
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => _open(context, ReportKind.pettyCash)),
              AccountsMenuCard(
                  title: 'Expenses Report',
                  subtitle: 'Bank and Petty Cash with matched-line totals',
                  icon: Icons.payments_outlined,
                  onTap: () => _open(context, ReportKind.expenses)),
              AccountsMenuCard(
                  title: 'Receivables Report',
                  subtitle: 'Authoritative ageing and outstanding balances',
                  icon: Icons.request_quote_outlined,
                  onTap: () => _open(context, ReportKind.receivables)),
            ]),
        const SizedBox(height: 22),
        const AccountsSectionTitle('Planned reports',
            subtitle:
                'Definitions and allocation policies are not yet implemented'),
        AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: 2.25,
            children: [
              for (final item in planned)
                AccountsMenuCard(
                    title: item.$1,
                    subtitle: 'Not yet implemented',
                    icon: item.$2,
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('${item.$1} is not yet implemented.')))),
            ]),
      ]),
    );
  }

  void _open(BuildContext context, ReportKind kind) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AccountsReportDetailScreen(
              session: session, api: api, kind: kind)));
}

enum ReportKind { pettyCash, expenses, receivables }

extension on ReportKind {
  String get title => switch (this) {
        ReportKind.pettyCash => 'Petty Cash Report',
        ReportKind.expenses => 'Expenses Report',
        ReportKind.receivables => 'Receivables Report',
      };
  String get endpoint => switch (this) {
        ReportKind.pettyCash => 'petty_cash_report.php',
        ReportKind.expenses => 'expense_report.php',
        ReportKind.receivables => 'receivables_report.php',
      };
  String get pdfEndpoint => switch (this) {
        ReportKind.pettyCash => 'petty_cash_audit_pack.php',
        ReportKind.expenses => 'expense_audit_pack.php',
        ReportKind.receivables => 'receivables_report_pdf.php',
      };
}

class AccountsReportDetailScreen extends StatefulWidget {
  const AccountsReportDetailScreen(
      {super.key,
      required this.session,
      required this.api,
      required this.kind});
  final CehSession session;
  final CehApiClient api;
  final ReportKind kind;
  @override
  State<AccountsReportDetailScreen> createState() =>
      _AccountsReportDetailScreenState();
}

class _AccountsReportDetailScreenState
    extends State<AccountsReportDetailScreen> {
  String _fromDate = '';
  String _toDate = '';
  final _reference = TextEditingController();
  final _paidTo = TextEditingController();
  final _custodian = TextEditingController();
  final _category = TextEditingController();
  final _client = TextEditingController();
  final _project = TextEditingController();
  final _equipment = TextEditingController();
  final _costCentre = TextEditingController();
  String _source = 'ALL';
  String _evidence = '';
  String _status = '';
  bool _busy = false;
  Map<String, dynamic>? _data;
  Object? _error;

  Map<String, String> get _filters {
    final result = <String, String>{};
    void add(String key, String value) {
      if (value.trim().isNotEmpty) result[key] = value.trim();
    }

    if (widget.kind == ReportKind.receivables) {
      add('as_of', _toDate);
    } else {
      add('date_from', _fromDate);
      add('date_to', _toDate);
      add('reference', _reference.text);
      add('paid_to', _paidTo.text);
      add('custodian', _custodian.text);
      add('category', _category.text);
      add('client', _client.text);
      add('project', _project.text);
      add('equipment', _equipment.text);
      add('cost_centre', _costCentre.text);
      add('status', _status);
      if (widget.kind == ReportKind.expenses && _source != 'ALL') {
        result['source'] = _source;
      }
      add('evidence', _evidence);
    }
    return result;
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.accountsReport(widget.session,
          endpoint: widget.kind.endpoint, filters: _filters);
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _busy = true);
    try {
      final file = await widget.api.accountsReportPdf(widget.session,
          endpoint: widget.kind.pdfEndpoint,
          filename: '${widget.kind.title.replaceAll(' ', '-')}.pdf',
          filters: _filters);
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          subject: widget.kind.title));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to export report: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.kind.title)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: 190,
              child: _ReportDatePickerField(
                  label: widget.kind == ReportKind.receivables
                      ? 'Invoice date from (optional)'
                      : 'Date from',
                  value: _fromDate,
                  onChanged: (value) => setState(() => _fromDate = value))),
          SizedBox(
              width: 190,
              child: _ReportDatePickerField(
                  label: widget.kind == ReportKind.receivables
                      ? 'As of date'
                      : 'Date to',
                  value: _toDate,
                  onChanged: (value) => setState(() => _toDate = value))),
          if (widget.kind != ReportKind.receivables) ...[
            SizedBox(
                width: 190,
                child: TextField(
                    controller: _reference,
                    decoration:
                        const InputDecoration(labelText: 'CEH reference'))),
            SizedBox(
                width: 220,
                child: TextField(
                    controller: _paidTo,
                    decoration: const InputDecoration(
                        labelText: 'Supplier / Paid To'))),
            if (widget.kind == ReportKind.pettyCash)
              SizedBox(
                  width: 190,
                  child: TextField(
                      controller: _custodian,
                      decoration:
                          const InputDecoration(labelText: 'Custodian'))),
            SizedBox(
                width: 190,
                child: TextField(
                    controller: _category,
                    decoration: const InputDecoration(
                        labelText: 'Category / account'))),
            SizedBox(
                width: 190,
                child: TextField(
                    controller: _client,
                    decoration: const InputDecoration(labelText: 'Client'))),
            SizedBox(
                width: 190,
                child: TextField(
                    controller: _project,
                    decoration: const InputDecoration(labelText: 'Project'))),
            SizedBox(
                width: 170,
                child: TextField(
                    controller: _equipment,
                    decoration: const InputDecoration(labelText: 'Equipment'))),
            SizedBox(
                width: 190,
                child: TextField(
                    controller: _costCentre,
                    decoration:
                        const InputDecoration(labelText: 'Cost Centre'))),
            SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      ('', 'All'),
                      ('DRAFT', 'Draft'),
                      ('SUBMITTED', 'Submitted'),
                      ('CORRECTION_REQUIRED', 'Needs Correction'),
                      ('APPROVED', 'Approved'),
                      ('VOIDED', 'Voided')
                    ]
                        .map((v) =>
                            DropdownMenuItem(value: v.$1, child: Text(v.$2)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? ''))),
            if (widget.kind == ReportKind.expenses)
              SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _source,
                      decoration: const InputDecoration(labelText: 'Source'),
                      items: const ['ALL', 'BANK', 'PETTY_CASH']
                          .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v == 'ALL'
                                  ? 'All'
                                  : v == 'BANK'
                                      ? 'Bank'
                                      : 'Petty Cash')))
                          .toList(),
                      onChanged: (v) => setState(() => _source = v ?? 'ALL'))),
            SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _evidence,
                    decoration:
                        const InputDecoration(labelText: 'Receipt / evidence'),
                    items: const [
                      ('', 'All'),
                      ('ATTACHED', 'Attached'),
                      ('MISSING', 'Missing')
                    ]
                        .map((v) =>
                            DropdownMenuItem(value: v.$1, child: Text(v.$2)))
                        .toList(),
                    onChanged: (v) => setState(() => _evidence = v ?? ''))),
          ],
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, children: [
          FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.refresh),
              label: const Text('Run report')),
          OutlinedButton.icon(
              onPressed: _busy ? null : _sharePdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(widget.kind == ReportKind.receivables
                  ? 'Export PDF'
                  : 'Export audit pack')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Unable to load report: $_error',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_data != null) ...[
          const SizedBox(height: 18),
          _ReportResults(kind: widget.kind, data: _data!)
        ],
      ]));
}

class _ReportResults extends StatelessWidget {
  const _ReportResults({required this.kind, required this.data});
  final ReportKind kind;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    if (kind == ReportKind.receivables) {
      final rows = data['invoices'] as List? ?? const [];
      final totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AccountsMetricLine(
            'Outstanding invoices', '${totals['invoice_count'] ?? 0}'),
        AccountsMetricLine('Total outstanding',
            formatNaira(double.tryParse('${totals['outstanding']}') ?? 0),
            prominent: true),
        for (final raw in rows)
          Builder(builder: (_) {
            final r = Map<String, dynamic>.from(raw as Map);
            return Card(
                child: ListTile(
                    title: Text(
                        '${r['reference']} • ${r['client_name_snapshot']}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        'Invoice ${displayAccountsDate('${r['invoice_date']}')} • Due ${r['due_date'] == null ? 'Not set' : displayAccountsDate('${r['due_date']}')} • ${r['days_overdue']} days overdue • ${r['bucket']}'),
                    trailing: Text(
                        formatNaira(
                            double.tryParse('${r['outstanding']}') ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w900))));
          }),
      ]);
    }
    final rows = data['rows'] as List? ?? const [];
    final totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AccountsMetricLine('Transactions', '${totals['transaction_count'] ?? 0}'),
      AccountsMetricLine('Matched-line total',
          formatNaira(double.tryParse('${totals['matched_amount']}') ?? 0),
          prominent: true),
      if ('${totals['matched_amount']}' != '${totals['header_amount']}')
        AccountsMetricLine('Full transaction context',
            formatNaira(double.tryParse('${totals['header_amount']}') ?? 0)),
      for (final raw in rows)
        Builder(builder: (_) {
          final r = Map<String, dynamic>.from(raw as Map);
          return Card(
              child: ExpansionTile(
                  title: Text('${r['reference_no']} • ${r['supplier_paid_to']}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${displayAccountsDate('${r['expense_date']}')} • ${r['source_type']} • ${r['status']}'),
                  trailing: Text(
                      formatNaira(
                          double.tryParse('${r['matched_amount']}') ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  childrenPadding: const EdgeInsets.all(16),
                  children: [
                AccountsMetricLine(
                    'Client', '${r['client_name'] ?? 'Not allocated'}'),
                AccountsMetricLine(
                    'Project', '${r['project_name'] ?? 'Not allocated'}'),
                AccountsMetricLine(
                    'Equipment', '${r['mixer_code'] ?? 'Not allocated'}'),
                AccountsMetricLine('Original Journal',
                    '${r['original_journal_reference'] ?? 'Not posted'}'),
                AccountsMetricLine(
                    'Evidence',
                    (int.tryParse('${r['evidence_count']}') ?? 0) > 0
                        ? 'Attached'
                        : 'No receipt attached'),
              ]));
        }),
    ]);
  }
}

class _ReportDatePickerField extends StatelessWidget {
  const _ReportDatePickerField(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseCanonicalAccountsDate(value) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(canonicalAccountsDate(picked));
  }

  @override
  Widget build(BuildContext context) => InkWell(
        key: ValueKey('report-date-$label'),
        onTap: () => _pick(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: value.isEmpty
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(
                    tooltip: 'Clear date',
                    onPressed: () => onChanged(''),
                    icon: const Icon(Icons.clear)),
          ),
          child:
              Text(value.isEmpty ? 'Select date' : displayAccountsDate(value)),
        ),
      );
}
