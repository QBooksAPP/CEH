import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/credit_note_pending.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/session.dart';
import 'accounts_billing_screen.dart';
import 'accounts_journal_screen.dart';

List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
int _id(dynamic value) => int.parse('$value');
String _money(dynamic value) => formatNgn(num.tryParse('$value') ?? 0);

class CreditNotesScreen extends StatefulWidget {
  const CreditNotesScreen(
      {super.key,
      required this.session,
      required this.invoiceId,
      this.api = const CehApiClient(),
      this.pendingStore = const CreditNotePendingStore()});
  final CehSession session;
  final int invoiceId;
  final CehApiClient api;
  final CreditNotePendingStore pendingStore;
  @override
  State<CreditNotesScreen> createState() => _CreditNotesScreenState();
}

class _CreditNotesScreenState extends State<CreditNotesScreen> {
  Map<String, dynamic>? _data, _pending;
  final _reason = TextEditingController();
  final Map<int, TextEditingController> _amounts = {}, _releases = {};
  String _date = canonicalAccountsDate(DateTime.now());
  String? _error;
  bool _busy = false, _loading = true, _dirty = false;
  bool get _admin => widget.session.user.isAdmin;
  @override
  void initState() {
    super.initState();
    if (_admin) _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final c in [..._amounts.values, ..._releases.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pending = await widget.pendingStore
          .load(widget.session.user.id, widget.invoiceId);
      final data = await widget.api
          .creditNotes(widget.session, {'invoice_id': '${widget.invoiceId}'});
      if (!mounted) return;
      for (final line in _rows(data['lines'])) {
        _amounts.putIfAbsent(_id(line['id']), TextEditingController.new);
        for (final a in _rows(line['production_allocations'])) {
          _releases.putIfAbsent(_id(a['id']), TextEditingController.new);
        }
      }
      setState(() {
        _data = data;
        _pending = pending;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _leave() async {
    if (_busy) return false;
    if (!_dirty || _pending != null) return true;
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Leave credit note?'),
                    content: const Text('Discard the unsubmitted form?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Stay')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Leave'))
                    ])) ??
        false;
  }

  Future<void> _open(int id) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CreditNoteDetailsScreen(
                session: widget.session, noteId: id, api: widget.api)));
    if (mounted) await _load();
  }

  Map<String, dynamic> _request() => {
        'invoice_id': widget.invoiceId,
        'credit_date': _date,
        'reason': _reason.text.trim(),
        'lines': [
          for (final line in _rows(_data!['lines']))
            if (_amounts[_id(line['id'])]!.text.trim().isNotEmpty)
              {
                'invoice_line_id': _id(line['id']),
                'gross_amount': _amounts[_id(line['id'])]!.text.trim(),
                'production_releases': [
                  for (final a in _rows(line['production_allocations']))
                    if (_releases[_id(a['id'])]!.text.trim().isNotEmpty)
                      {
                        'invoice_production_allocation_id': _id(a['id']),
                        'released_m3': _releases[_id(a['id'])]!.text.trim(),
                      }
                ],
              }
        ],
      };
  Future<void> _review() async {
    if (_busy || _pending != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = _request();
      final response =
          await widget.api.quoteCreditNote(widget.session, request);
      final quote = Map<String, dynamic>.from(response['quote'] as Map);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Review Credit Note'),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(displayAccountsDate(_date)),
                        Text(request['reason'] as String),
                        for (final line in _rows(quote['lines'])) ...[
                          const Divider(),
                          Text('${(line['original'] as Map)['description']}'),
                          Text(
                              'Net ${_money(line['net_amount'])} • VAT ${_money(line['vat_amount'])} • Credit ${_money(line['gross_amount'])}'),
                          for (final release
                              in _rows(line['production_releases']))
                            Text(
                                'Explicit production release: ${release['released_m3']} m³'),
                        ],
                        const Divider(),
                        Text('Total credit: ${_money(quote['total_amount'])}'),
                        Text(
                            'Invoice outstanding after credit: ${_money(quote['outstanding_after'])}'),
                        const SizedBox(height: 12),
                        const Text(
                            'Issued Credit Notes are immutable. Check every amount and quantity before confirming.'),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Back')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm Issue Credit Note'))
                  ]));
      if (confirmed != true || !mounted) return;
      request['request_key'] = CreditNotePendingStore.newKey();
      await widget.pendingStore
          .save(widget.session.user.id, widget.invoiceId, request);
      _pending = request;
      await _submitPending();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completed(Map<String, dynamic> result) async {
    await widget.pendingStore.clear(widget.session.user.id, widget.invoiceId);
    if (!mounted) return;
    setState(() {
      _pending = null;
      _dirty = false;
      _busy = false;
    });
    _reason.clear();
    for (final c in [..._amounts.values, ..._releases.values]) {
      c.clear();
    }
    await _open(_id((result['credit_note'] as Map)['id']));
  }

  Future<void> _submitPending() async {
    try {
      await _completed(
          await widget.api.issueCreditNote(widget.session, _pending!));
    } on ApiException catch (e) {
      // Only a locked, authoritative business rejection resolves an issuance.
      // Authentication/gateway errors cannot prove that an earlier POST failed.
      if (const {
        'CREDIT_EXCEEDS_OUTSTANDING',
        'CREDIT_EXCEEDS_INVOICE_LINE',
        'ISSUED_INVOICE_REQUIRED',
        'NO_OUTSTANDING_BALANCE',
        'QUANTITY_RELEASE_EXCEEDS_ALLOCATION_M3',
        'PRODUCTION_ALLOCATION_RELEASE_MISMATCH',
        'CREDIT_DATE_BEFORE_INVOICE',
      }.contains(e.code)) {
        await widget.pendingStore
            .clear(widget.session.user.id, widget.invoiceId);
        _pending = null;
        if (mounted) await _load();
      }
      rethrow;
    }
  }

  Future<void> _resolve() async {
    if (_busy || _pending == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.creditNotes(
          widget.session, {'request_key': '${_pending!['request_key']}'});
      if (result['completed'] == true) {
        await _completed(Map<String, dynamic>.from(result['result'] as Map));
      } else {
        await _submitPending();
      } // Retry the identical persisted request, never a new key.
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Outcome not confirmed: $e. Resolve this request before issuing another.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return PopScope(
        canPop: !_busy && !_dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && await _leave() && mounted) {
            setState(() => _dirty = false);
            if (context.mounted) Navigator.pop(context);
          }
        },
        child: Scaffold(
            appBar: AppBar(
                title: const Text('Credit Notes'),
                actions: cehHomeAction(context, canLeave: _leave)),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(18), children: [
                    if (_error != null)
                      Text(_error!, key: const ValueKey('credit-note-error')),
                    if (_data == null)
                      TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('Retry')),
                    if (_busy) const LinearProgressIndicator(),
                    if (_pending != null) ...[
                      const Text(
                          'A previous issuance needs its outcome confirmed. No new request can be started.'),
                      FilledButton(
                          onPressed: _busy ? null : _resolve,
                          child: const Text('Resolve / retry same request')),
                    ],
                  if (_data != null) ...[
                    if (_data!['invoice'] is Map) ...[
                      Text('${(_data!['invoice'] as Map)['reference']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('${(_data!['invoice'] as Map)['client_name_snapshot']}'),
                    ],
                      Text(
                          'Invoice outstanding: ${_money(_data!['outstanding'])}'),
                      for (final note in _rows(_data!['credit_notes']))
                        ListTile(
                            title: Text('${note['reference']}'),
                            subtitle: Text(
                                '${displayAccountsDate('${note['credit_date']}')} • ${_money(note['total_amount'])}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _busy ? null : () => _open(_id(note['id']))),
                      if (_rows(_data!['credit_notes']).isEmpty)
                        const Text('No Credit Notes issued.'),
                      const Divider(),
                      if (_data!['can_issue_credit_note'] != true)
                        Text(
                            'Credit unavailable: ${(_data!['blocking_reasons'] as List).join(', ')}'),
                      if (_data!['can_issue_credit_note'] == true &&
                          _pending == null) ...[
                        Text('Issue Credit Note',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text(
                            'Enter a gross credit for each selected line. Leave other lines blank. VAT is calculated by the server.'),
                        for (final line in _rows(_data!['lines']))
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${line['description']}'),
                                        Text(
                                            'Original: ${_money(line['gross_amount'])} • Previously credited: ${_money(line['credited_gross'])}'),
                                        Text(
                                            'Remaining net ${_money(line['remaining_net'])} • VAT ${_money(line['remaining_vat'])} • Gross ${_money(line['remaining_gross'])}'),
                                        TextField(
                                            controller:
                                                _amounts[_id(line['id'])],
                                            enabled: !_busy,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            onChanged: (_) =>
                                                setState(() => _dirty = true),
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Gross amount to credit')),
                                        for (final a in _rows(line[
                                            'production_allocations'])) ...[
                                          Text(
                                              '${a['report_reference_snapshot']}: originally billed ${a['billed_m3']} m³; released ${a['released_m3']} m³; remaining ${a['remaining_releasable_m3']} m³'),
                                          TextField(
                                              controller:
                                                  _releases[_id(a['id'])],
                                              enabled: !_busy,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                              onChanged: (_) =>
                                                  setState(() => _dirty = true),
                                              decoration: const InputDecoration(
                                                  labelText:
                                                      'Explicit release (m³), optional',
                                                  helperText:
                                                      'Leave blank for a price-only credit.')),
                                        ],
                                      ]))),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final date = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.parse(_date),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100));
                                    if (date != null && mounted) {
                                      setState(() {
                                        _date = canonicalAccountsDate(date);
                                        _dirty = true;
                                      });
                                    }
                                  },
                            child: Text(
                                'Credit date: ${displayAccountsDate(_date)}')),
                        TextField(
                            controller: _reason,
                            enabled: !_busy,
                            maxLength: 500,
                            maxLines: 3,
                            onChanged: (_) => setState(() => _dirty = true),
                            decoration: const InputDecoration(
                                labelText: 'Reason (required)')),
                        FilledButton(
                            onPressed: _busy ? null : _review,
                            child: const Text('Review Credit Note')),
                      ],
                    ],
                  ])));
  }
}

class CreditNoteDocuments extends StatefulWidget {
  const CreditNoteDocuments(
      {super.key,
      required this.session,
      required this.api,
      required this.noteId,
      required this.initialEvidence});
  final CehSession session;
  final CehApiClient api;
  final int noteId;
  final List<Map<String, dynamic>> initialEvidence;
  @override
  State<CreditNoteDocuments> createState() => _CreditNoteDocumentsState();
}

class _CreditNoteDocumentsState extends State<CreditNoteDocuments> {
  late List<Map<String, dynamic>> _evidence = widget.initialEvidence;
  bool _busy = false;
  String? _error;
  Future<void> _view([int? evidenceId]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = evidenceId == null
          ? await widget.api.creditNotePdf(widget.session, widget.noteId)
          : await widget.api.financialEvidence(widget.session, evidenceId);
      final filename =
          result.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}cn-${widget.noteId}-$filename');
      await file.writeAsBytes(result.bytes, flush: true);
      if (!mounted) return;
      setState(() => _busy = false);
      await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], subject: 'CEH Credit Note'));
    } catch (e) {
      if (mounted) setState(() => _error = 'Document could not be opened: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await widget.api.uploadFinancialEvidenceRecord(widget.session,
          sourceType: 'CREDIT_NOTE',
          sourceRecordId: widget.noteId,
          filename: file.name,
          mimeType: file.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg',
          bytes: await file.readAsBytes());
      final result = await widget.api
          .creditNotes(widget.session, {'id': '${widget.noteId}'});
      if (mounted) {
        setState(() =>
            _evidence = _rows((result['credit_note'] as Map)['evidence']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Evidence upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        OutlinedButton.icon(
            onPressed: _busy ? null : () => _view(),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Open Credit Note PDF')),
        const Text('Supporting evidence (optional)'),
        for (final e in _evidence)
          TextButton(
              onPressed: _busy ? null : () => _view(_id(e['id'])),
              child: Text('${e['original_filename']}')),
        if (_evidence.isEmpty) const Text('No evidence attached.'),
        OutlinedButton(
            onPressed: _busy ? null : _attach,
            child: const Text('Attach evidence image')),
      ]);
}

class CreditNoteDetailsScreen extends StatelessWidget {
  const CreditNoteDetailsScreen(
      {super.key,
      required this.session,
      required this.noteId,
      required this.api});
  final CehSession session;
  final int noteId;
  final CehApiClient api;
  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return Scaffold(
        appBar: AppBar(
            title: const Text('Credit Note Details'),
            actions: cehHomeAction(context)),
        body: FutureBuilder<Map<String, dynamic>>(
            future: api.creditNotes(session, {'id': '$noteId'}),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text('Credit Note unavailable: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final note = Map<String, dynamic>.from(
                  snapshot.data!['credit_note'] as Map);
              return ListView(padding: const EdgeInsets.all(18), children: [
                Text('${note['reference']}',
                    style: Theme.of(context).textTheme.headlineSmall),
                Text('${note['status']} • ${note['client']}'),
                Text(
                    'Credit date: ${displayAccountsDate('${note['credit_date']}')}'),
                Text('Issued by: ${note['issued_by_name'] ?? 'Not recorded'}'),
                Text(
                    'Recorded: ${displayCehDateTime('${note['issued_at']}Z')}'),
                Text('Reason: ${note['reason']}'),
                const Text('Issued Credit Notes are immutable.'),
                TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => InvoiceDetailsScreen(
                                invoiceId: _id(note['invoice_id']),
                                session: session,
                                api: api))),
                    child:
                        Text('Original invoice: ${note['invoice_reference']}')),
                if (note['journal_id'] != null)
                  TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => JournalDetailScreen(
                                  session: session,
                                  api: api,
                                  journalId: _id(note['journal_id'])))),
                      child: Text('Journal: ${note['journal_reference']}')),
                for (final line in _rows(note['lines']))
                  ListTile(
                      title: Text('${line['description']}'),
                      subtitle: Text(
                          'Net ${_money(line['net_amount'])} • VAT ${_money(line['vat_amount'])}'),
                      trailing: Text(_money(line['gross_amount']))),
                Text('Net: ${_money(note['net_amount'])}'),
                Text('VAT: ${_money(note['vat_amount'])}'),
                Text('Total credit: ${_money(note['total_amount'])}'),
                if (note['document'] is Map)
                  Text(
                      'Outstanding immediately after issuance: ${_money((note['document'] as Map)['outstanding_after'])}'),
                Text(
                    'Current invoice outstanding: ${_money(note['current_invoice_outstanding'])}'),
                for (final r in _rows(note['production_releases']))
                  Text(
                      '${r['report_reference_snapshot']}: released ${r['released_m3']} m³'),
                if (_rows(note['production_releases']).isEmpty)
                  const Text('No production quantity released.'),
                CreditNoteDocuments(
                    session: session,
                    api: api,
                    noteId: noteId,
                    initialEvidence: _rows(note['evidence'])),
              ]);
            }));
  }
}
