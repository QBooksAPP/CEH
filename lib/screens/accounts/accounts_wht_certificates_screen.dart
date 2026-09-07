import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts.dart';
import '../../models/session.dart';

class WhtCertificatesScreen extends StatefulWidget {
  const WhtCertificatesScreen(
      {super.key, required this.session, this.api = const CehApiClient()});
  final CehSession session;
  final CehApiClient api;
  @override
  State<WhtCertificatesScreen> createState() => _WhtCertificatesScreenState();
}

class _WhtCertificatesScreenState extends State<WhtCertificatesScreen> {
  String _status = 'PENDING', _search = '', _from = '', _to = '';
  bool _busy = false;
  late Future<List<WhtCertificateRecord>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      _future = widget.api.whtCertificates(widget.session, filters: {
        'status': _status,
        'search': _search,
        'date_from': _from,
        'date_to': _to
      });
  void _reload() => setState(_load);
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _filters() async {
    final search = TextEditingController(text: _search),
        from = TextEditingController(text: _from),
        to = TextEditingController(text: _to);
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('WHT certificate filters'),
                content: SizedBox(
                    width: 420,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                              labelText: 'Certificate status'),
                          items: const [
                            DropdownMenuItem(
                                value: 'PENDING', child: Text('Pending')),
                            DropdownMenuItem(
                                value: 'RECEIVED', child: Text('Received')),
                            DropdownMenuItem(value: 'ALL', child: Text('All'))
                          ],
                          onChanged: (v) => _status = v ?? 'PENDING'),
                      TextField(
                          controller: search,
                          decoration: const InputDecoration(
                              labelText:
                                  'Client, receipt or invoice reference')),
                      TextField(
                          controller: from,
                          decoration: const InputDecoration(
                              labelText: 'From date (YYYY-MM-DD)')),
                      TextField(
                          controller: to,
                          decoration: const InputDecoration(
                              labelText: 'To date (YYYY-MM-DD)'))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, {
                            'search': search.text.trim(),
                            'date_from': from.text.trim(),
                            'date_to': to.text.trim()
                          }),
                      child: const Text('Apply'))
                ]));
    if (result != null) {
      _search = result['search']!;
      _from = result['date_from']!;
      _to = result['date_to']!;
      _reload();
    }
  }

  Future<void> _receive(WhtCertificateRecord record) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final lower = picked.name.toLowerCase();
      final evidenceId = await widget.api.uploadFinancialEvidenceRecord(
          widget.session,
          sourceType: 'WHT_CERTIFICATE',
          sourceRecordId: record.receiptId,
          filename: picked.name,
          mimeType: lower.endsWith('.png') ? 'image/png' : 'image/jpeg',
          bytes: await picked.readAsBytes());
      await widget.api
          .markWhtCertificateReceived(widget.session, record, evidenceId);
      if (mounted) {
        _message('WHT certificate marked as received.');
        _reload();
      }
    } on ApiException catch (e) {
      if (mounted) _message(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(WhtCertificateRecord record) async {
    if (record.evidenceId == null) return;
    setState(() => _busy = true);
    try {
      final evidence = await widget.api
          .financialEvidence(widget.session, record.evidenceId!);
      final safe =
          evidence.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file =
          File('${Directory.systemTemp.path}${Platform.pathSeparator}$safe');
      await file.writeAsBytes(evidence.bytes, flush: true);
      if (mounted) setState(() => _busy = false);
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)], subject: 'CEH WHT Certificate'));
    } on ApiException catch (e) {
      if (mounted) _message(e.code);
    } catch (_) {
      if (mounted) _message('WHT_CERTIFICATE_VIEW_FAILED');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    return Scaffold(
      appBar: AppBar(
          title: const Text('WHT Certificates',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: cehHomeAction(context)),
      body: Stack(children: [
        FutureBuilder<List<WhtCertificateRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('WHT Certificates unavailable: ${snapshot.error}'),
                OutlinedButton(
                    onPressed: _reload, child: const Text('Try again'))
              ]));
            }
            final rows = snapshot.data!;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text('${rows.length} certificate records',
                          style: Theme.of(context).textTheme.titleMedium)),
                  OutlinedButton.icon(
                      key: const ValueKey('wht-filter'),
                      onPressed: _busy ? null : _filters,
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Filters'))
                ]),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No WHT certificates match these filters.'))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _certificateTile(rows[index])),
              )
            ]);
          },
        ),
        if (_busy)
          const Positioned.fill(
              child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator())))
      ]),
    );
  }

  Widget _certificateTile(WhtCertificateRecord record) => ListTile(
        key: ValueKey('wht-${record.recordType}-${record.recordId}'),
        leading: Icon(record.isPending
            ? Icons.schedule_outlined
            : Icons.description_outlined),
        title: Text(record.client,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${record.receiptReference}${record.invoiceReference == null ? '' : ' • ${record.invoiceReference}'}\n'
            '${displayAccountsDate(record.paymentDate)} • ${formatAccountsStatus(record.status)}\n'
            'Evidence: ${record.evidenceId == null ? 'Not attached' : 'Attached'}'),
        isThreeLine: true,
        trailing: Text(formatNgn(record.amount),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        onTap: () => _details(record),
      );

  Future<void> _details(WhtCertificateRecord record) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(record.client,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(
                        '${record.receiptReference}${record.invoiceReference == null ? '' : ' • ${record.invoiceReference}'}'),
                    Text(
                        'Payment date: ${displayAccountsDate(record.paymentDate)}'),
                    Text('WHT amount: ${formatNgn(record.amount)}'),
                    Text('Status: ${formatAccountsStatus(record.status)}'),
                    if (record.receivedAt != null)
                      Text(
                          'Received: ${displayAccountsDate(record.receivedAt!)}'),
                    const SizedBox(height: 14),
                    if (record.isPending)
                      FilledButton.icon(
                          key: const ValueKey('receive-wht-certificate'),
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _receive(record);
                                },
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                              'Attach certificate and mark received')),
                    if (!record.isPending && record.evidenceId != null)
                      OutlinedButton.icon(
                          key: const ValueKey('view-wht-certificate'),
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _view(record);
                                },
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View attached certificate'))
                  ]))));
}
