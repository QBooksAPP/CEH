import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/accounts_formatters.dart';
import '../../core/api_client.dart';
import '../../core/bank_statement_upload.dart';
import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/bank_import_preview.dart';
import '../../models/banking_workspace.dart';
import '../../models/session.dart';

class BankStatementImportScreen extends StatefulWidget {
  const BankStatementImportScreen(
      {super.key,
      required this.session,
      required this.bank,
      this.api = const CehApiClient(),
      this.picker = pickBankStatement});
  final CehSession session;
  final Map<String, dynamic> bank;
  final CehApiClient api;
  final Future<BankStatementFile?> Function() picker;
  @override
  State<BankStatementImportScreen> createState() => _ImportState();
}

class _ImportState extends State<BankStatementImportScreen> {
  BankStatementFile? file;
  BankImportPreview? preview;
  Map<String, dynamic>? completed;
  bool busy = false, picking = false;
  double progress = 0;
  String? error;
  int? documentId;
  Future<void> choose() async {
    // External picker never owns CEH's busy/progress state or navigation barrier.
    if (picking) return;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final selected = await widget.picker();
      if (!mounted || selected == null) return;
      selected.validate();
      setState(() {
        file = selected;
        preview = null;
        completed = null;
        documentId = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => error = 'Choose a readable CSV/XLSX statement up to 10 MB.');
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  String message(Object e) {
    if (e is TimeoutException) {
      return 'Request timed out. Retry safely; the same file/import will not be duplicated.';
    }
    if (e is ApiException && e.code == 'PREVIEW_CHANGED') {
      return 'Preview changed. Reload the preview and review it before confirming.';
    }
    if (e is ApiException) {
      return 'Statement request rejected: ${e.code}. Review the file or reload the preview.';
    }
    return 'Could not complete the request. Check your connection and retry safely.';
  }

  Future<void> upload() async {
    if (busy || file == null) return;
    setState(() {
      busy = true;
      error = null;
      progress = 0;
      preview = null;
    });
    try {
      if (documentId == null) {
        final result = await widget.api.uploadBankStatement(
            widget.session, bankInt(widget.bank['id']), file!, (p) {
          if (mounted) setState(() => progress = p);
        });
        documentId = bankInt(result['document_id']);
      }
      final json = await widget.api.bankingRead(widget.session,
          'bank_statement_preview.php', {'document_id': '$documentId'});
      final p = BankImportPreview(json);
      if (bankInt(p.document['bank_account_id']) !=
          bankInt(widget.bank['id'])) {
        throw const ApiException('STATEMENT_BANK_MISMATCH');
      }
      if (mounted) setState(() => preview = p);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm() async {
    if (busy || preview?.canConfirm != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.confirmBankStatement(
          widget.session, preview!.documentId, preview!.confirmation);
      if (mounted) setState(() => completed = result);
    } catch (e) {
      // On uncertain completion, reload before offering another confirmation.
      if (mounted) {
        setState(() {
          error = message(e);
          preview = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget pair(String label, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text('$label: ${value ?? 'Not available'}'));
  String money(Object? v) => v == null
      ? 'Not available'
      : formatCurrency(num.tryParse('$v') ?? 0,
          currencyCode: bankText(widget.bank['currency']));
  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, widget.session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    final p = preview, s = preview?.summary ?? {};
    return PopScope(
        canPop: !busy,
        child: Scaffold(
            appBar: AppBar(
                title: const Text('Import Statement'),
                actions: cehHomeAction(context, canLeave: () async => !busy)),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Text(bankAccountLabel(widget.bank)),
              const Text(
                  'Zenith Activity Statement format • CSV / XLSX • maximum 10 MB'),
              if (completed == null) ...[
                OutlinedButton(
                    onPressed: busy || picking ? null : choose,
                    child: const Text('Choose CSV/XLSX')),
                if (file != null) ...[
                  pair('Filename', file!.name),
                  pair('File size', '${file!.bytes.length} bytes'),
                  if (p == null)
                    FilledButton(
                        onPressed: busy ? null : upload,
                        child: Text(documentId == null
                            ? 'Upload & Preview'
                            : 'Reload Preview')),
                ],
              ],
              if (busy) ...[
                LinearProgressIndicator(
                    value: progress > 0 && progress < 1 ? progress : null),
                const Text('Processing securely…')
              ],
              if (error != null) Text(error!),
              if (p != null && completed == null) ...[
                pair('Statement', p.document['original_filename']),
                pair('Period',
                    '${displayAccountsDate(bankText(s['statement_from']))} – ${displayAccountsDate(bankText(s['statement_to']))}'),
                pair('Transactions', s['total_rows']),
                pair('Debits (${s['debits_count']})', money(s['debits_value'])),
                pair('Credits (${s['credits_count']})',
                    money(s['credits_value'])),
                pair('Opening balance', money(s['opening_balance'])),
                pair('Closing balance', money(s['closing_balance'])),
                pair(
                    'Balance reconciliation',
                    s['balance_reconciles'] == true
                        ? 'Reconciles'
                        : 'Not verified — review reasons below'),
                pair('Invalid rows', s['invalid_rows']),
                pair('Already-imported source rows',
                    s['already_imported_source_rows']),
                pair('Ambiguous overlap rows', p.ambiguousRows),
                for (final reason in (s['errors'] as List? ?? []))
                  Text('Blocking reason: $reason'),
                if (p.ambiguousRows > 0)
                  const Text(
                      'Overlapping source transactions require review. Import is blocked.'),
                if (p.alreadyImported) ...[
                  const Text('This statement has already been imported.'),
                  pair('Existing import', p.batchId),
                  if (p.json['imported_at'] != null)
                    pair('Imported',
                        displayCehDateTime(bankText(p.json['imported_at']))),
                ] else ...[
                  const Text(
                      'Importing a bank statement records the bank transactions in CEH. It does not create Expenses, Client Payments or accounting journals.'),
                  FilledButton(
                      onPressed: busy || !p.canConfirm ? null : confirm,
                      child: const Text('Confirm Import')),
                  TextButton(
                      onPressed: busy ? null : upload,
                      child: const Text('Reload Preview')),
                ],
              ],
              if (completed != null) ...[
                const Text('Statement import completed.'),
                pair('Import', completed!['batch_id']),
                pair('Imported transactions',
                    completed!['imported'] ?? s['total_rows']),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Return to Banking')),
              ],
            ])));
  }
}
