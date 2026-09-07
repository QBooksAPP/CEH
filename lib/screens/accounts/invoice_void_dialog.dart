import 'package:flutter/material.dart';
import '../../core/accounts_formatters.dart';
import '../../models/accounts.dart';

class InvoiceVoidRequest {
  const InvoiceVoidRequest(this.reason, this.date);
  final String reason, date;
}

class InvoiceVoidDialog extends StatefulWidget {
  const InvoiceVoidDialog({super.key, required this.invoice});
  final BillingInvoiceDetail invoice;
  @override
  State<InvoiceVoidDialog> createState() => _InvoiceVoidDialogState();
}

class _InvoiceVoidDialogState extends State<InvoiceVoidDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String _date = canonicalAccountsDate(DateTime.now());
  bool _confirmed = false;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Void Invoice?'),
        content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.invoice.reference),
                          Text(widget.invoice.client),
                          Text('Total: ${formatNgn(widget.invoice.total)}'),
                          Text(
                              'Outstanding: ${formatNgn(widget.invoice.outstanding)}'),
                          const SizedBox(height: 12),
                          const Text(
                              'This auditable accounting action changes the invoice to VOID, creates a reversal of its original financial journal, and reverses committed production/billing allocations. It does not delete the invoice, journal or production records.'),
                          const SizedBox(height: 12),
                          AccountsDatePickerField(
                              label: 'Void date',
                              initialCanonicalDate: _date,
                              onChanged: (value) => _date = value),
                          TextFormField(
                              key: const ValueKey('invoice-void-reason'),
                              controller: _reason,
                              decoration:
                                  const InputDecoration(labelText: 'Reason'),
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 500,
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Reason is required.'
                                  : null),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _confirmed,
                              title: const Text(
                                  'I confirm this invoice should be voided.'),
                              onChanged: (value) =>
                                  setState(() => _confirmed = value ?? false)),
                        ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('confirm-void-invoice'),
              onPressed: !_confirmed
                  ? null
                  : () {
                      if (_form.currentState!.validate()) {
                        Navigator.pop(context,
                            InvoiceVoidRequest(_reason.text.trim(), _date));
                      }
                    },
              child: const Text('Confirm Void Invoice'))
        ],
      );
}
