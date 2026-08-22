import 'package:flutter/material.dart';

import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts_mock_data.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';

class _PhaseAccountsPage extends StatelessWidget {
  const _PhaseAccountsPage({
    required this.session,
    required this.title,
    required this.children,
  });

  final CehSession session;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
        body: Center(child: Text('Administrator access required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: cehHomeAction(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          const PrototypeBanner(),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

void _prototypeNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Prototype only — $message')),
  );
}

class BankingPrototypeScreen extends StatelessWidget {
  const BankingPrototypeScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) {
    final bank = AccountsMockData.bankAccounts.first;
    return _PhaseAccountsPage(
      session: session,
      title: 'Banking',
      children: [
        const AccountsSectionTitle(
          'Bank accounts',
          subtitle: 'Balances and reconciliation are illustrative only',
        ),
        Card(
          key: const ValueKey('bank-account-zenith'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    CircleAvatar(child: Icon(Icons.account_balance_outlined)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Zenith Bank',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w900)),
                    ),
                    AccountsStatusChip('Active'),
                  ],
                ),
                const SizedBox(height: 14),
                AccountsMetricLine(
                    'Current CEH balance', formatNaira(bank.currentBalance)),
                AccountsMetricLine(
                    'Statement balance', formatNaira(bank.statementBalance)),
                AccountsMetricLine(
                    'Unreconciled transactions', '${bank.unreconciledCount}'),
                const Divider(height: 26),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('import-bank-statement'),
                      onPressed: null,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import Statement — format mapping pending'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _prototypeNotice(
                          context, 'no bank transaction was created.'),
                      icon: const Icon(Icons.add),
                      label: const Text('Manual Transaction'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const AccountsSectionTitle(
          'Reconciliation workspace',
          subtitle:
              'Statement rows are matched before any new transaction is created',
        ),
        for (final row in AccountsMockData.bankTransactions)
          Card(
            child: ExpansionTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(row.description,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text(
                    '${row.amount < 0 ? '−' : '+'}${formatNaira(row.amount.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: row.amount < 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Expanded(child: Text('${row.date} • Ref ${row.reference}')),
                  AccountsStatusChip(row.status),
                ],
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AccountsStatusChip(row.status),
                ),
                if (row.status == 'Potential Match') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Suggested match: existing Zenith → Segun funding, ref 01310.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => _prototypeNotice(
                          context, 'the suggested match was not confirmed.'),
                      child: const Text('Review Match'),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class PettyCashCustodianPrototypeScreen extends StatelessWidget {
  const PettyCashCustodianPrototypeScreen({
    super.key,
    required this.session,
  });
  final CehSession session;

  @override
  Widget build(BuildContext context) {
    final custodians = AccountsMockData.pettyCashCustodians;
    final total = custodians.fold<double>(0, (sum, item) => sum + item.balance);
    return _PhaseAccountsPage(
      session: session,
      title: 'Petty Cash',
      children: [
        SizedBox(
          height: 190,
          child: AccountsSummaryCard(
            label: 'TOTAL PETTY CASH',
            value: total,
            detail:
                'Across ${custodians.length} independent custodian accounts',
            icon: Icons.account_balance_wallet_outlined,
            emphasized: true,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const ValueKey('fund-petty-cash'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FundPettyCashPrototypeScreen(session: session),
                ),
              ),
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('Fund Petty Cash'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('add-petty-cash-expense'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddPettyCashExpensePrototypeScreen(
                    session: session,
                  ),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Add Petty Cash Expense'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const AccountsSectionTitle(
          'Custodian balances',
          subtitle: 'Funds and spending remain independent for each custodian',
        ),
        AccountsResponsiveGrid(
          tabletColumns: 2,
          desktopColumns: 3,
          childAspectRatio: 0.95,
          children: [
            for (final custodian in custodians)
              Card(
                key: ValueKey('custodian-${custodian.name.toLowerCase()}'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(custodian.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      Text(custodian.role,
                          style: const TextStyle(color: Colors.black54)),
                      const Spacer(),
                      AccountsMetricLine('Funds Received',
                          formatNaira(custodian.fundsReceived)),
                      AccountsMetricLine('Accounted / Spent',
                          formatNaira(custodian.accounted)),
                      AccountsMetricLine('Pending Approval',
                          formatNaira(custodian.pendingApproval)),
                      AccountsMetricLine(
                          'Balance', formatNaira(custodian.balance),
                          prominent: true),
                      if (custodian.pendingApproval > 0)
                        Text(
                          'Available after reservation: ${formatNaira(custodian.availableBalance)}',
                          style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CustodianTransactionsPrototypeScreen(
                              session: session,
                              custodian: custodian,
                            ),
                          ),
                        ),
                        child: const Text('View Transactions'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class FundPettyCashPrototypeScreen extends StatefulWidget {
  const FundPettyCashPrototypeScreen({super.key, required this.session});
  final CehSession session;

  @override
  State<FundPettyCashPrototypeScreen> createState() =>
      _FundPettyCashPrototypeScreenState();
}

class _FundPettyCashPrototypeScreenState
    extends State<FundPettyCashPrototypeScreen> {
  String _custodian = 'Felix';

  @override
  Widget build(BuildContext context) => _PhaseAccountsPage(
        session: widget.session,
        title: 'Fund Petty Cash',
        children: [
          const AccountsSectionTitle(
            'Asset transfer',
            subtitle: 'Funding is not an expense • preview only',
          ),
          const TextField(
            enabled: false,
            decoration: InputDecoration(
                labelText: 'From Account', hintText: 'Zenith Bank'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('fund-custodian'),
            initialValue: _custodian,
            decoration: const InputDecoration(labelText: 'To Custodian'),
            items: AccountsMockData.pettyCashCustodians
                .map((item) =>
                    DropdownMenuItem(value: item.name, child: Text(item.name)))
                .toList(),
            onChanged: (value) => setState(() => _custodian = value ?? 'Felix'),
          ),
          const SizedBox(height: 12),
          const TextField(
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Amount (₦)'),
          ),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today_outlined)),
          ),
          const SizedBox(height: 12),
          const TextField(
              decoration:
                  InputDecoration(labelText: 'Bank transfer / reference')),
          const SizedBox(height: 12),
          const TextField(
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Description / notes')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                _prototypeNotice(context, 'no proof was selected.'),
            icon: const Icon(Icons.attach_file),
            label: const Text('Optional Transfer Proof'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Entered by'),
            subtitle: Text(widget.session.user.fullName),
          ),
          FilledButton.icon(
            onPressed: () =>
                _prototypeNotice(context, 'funding was not saved.'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview Funding'),
          ),
        ],
      );
}

class AddPettyCashExpensePrototypeScreen extends StatefulWidget {
  const AddPettyCashExpensePrototypeScreen({
    super.key,
    required this.session,
  });
  final CehSession session;

  @override
  State<AddPettyCashExpensePrototypeScreen> createState() =>
      _AddPettyCashExpensePrototypeScreenState();
}

class _AddPettyCashExpensePrototypeScreenState
    extends State<AddPettyCashExpensePrototypeScreen> {
  String _custodian = 'Segun';
  bool _noReceipt = false;

  @override
  Widget build(BuildContext context) => _PhaseAccountsPage(
        session: widget.session,
        title: 'Add Petty Cash Expense',
        children: [
          const AccountsSectionTitle(
            'Expense submission',
            subtitle: 'DRAFT → SUBMITTED → APPROVED / REJECTED',
          ),
          DropdownButtonFormField<String>(
            initialValue: _custodian,
            decoration: const InputDecoration(labelText: 'Custodian'),
            items: AccountsMockData.pettyCashCustodians
                .map((item) =>
                    DropdownMenuItem(value: item.name, child: Text(item.name)))
                .toList(),
            onChanged: (value) => setState(() => _custodian = value ?? 'Segun'),
          ),
          const SizedBox(height: 12),
          const TextField(decoration: InputDecoration(labelText: 'Date')),
          const SizedBox(height: 12),
          const TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Amount (₦)')),
          const SizedBox(height: 12),
          const TextField(decoration: InputDecoration(labelText: 'Category')),
          const SizedBox(height: 12),
          const TextField(
              decoration: InputDecoration(labelText: 'Supplier / Paid To')),
          const SizedBox(height: 12),
          const TextField(
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Description')),
          const SizedBox(height: 12),
          const TextField(
              decoration:
                  InputDecoration(labelText: 'Client / Project (optional)')),
          const SizedBox(height: 12),
          const TextField(
              decoration: InputDecoration(labelText: 'Equipment (optional)')),
          const SizedBox(height: 18),
          const AccountsSectionTitle('Receipt / evidence'),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('take-receipt-photo'),
                onPressed: _noReceipt
                    ? null
                    : () => _prototypeNotice(context, 'camera was not opened.'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take Photo'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('choose-receipt-photo'),
                onPressed: _noReceipt
                    ? null
                    : () => _prototypeNotice(context, 'no photo was selected.'),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose Existing Photo'),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _noReceipt,
            title: const Text('No Receipt'),
            onChanged: (value) => setState(() => _noReceipt = value ?? false),
          ),
          if (_noReceipt)
            const TextField(
              key: ValueKey('no-receipt-reason'),
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Reason (required)'),
            ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('Entered by'),
            subtitle: Text(widget.session.user.fullName),
          ),
          FilledButton.icon(
            onPressed: () =>
                _prototypeNotice(context, 'expense was not saved.'),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Preview Submission'),
          ),
        ],
      );
}

class CustodianTransactionsPrototypeScreen extends StatelessWidget {
  const CustodianTransactionsPrototypeScreen({
    super.key,
    required this.session,
    required this.custodian,
  });
  final CehSession session;
  final PettyCashCustodian custodian;

  @override
  Widget build(BuildContext context) => _PhaseAccountsPage(
        session: session,
        title: '${custodian.name} Petty Cash',
        children: [
          AccountsSectionTitle('Transaction history', subtitle: custodian.role),
          for (final entry in AccountsMockData.custodianCashEntries
              .where((entry) => entry.custodian == custodian.name))
            Card(
              child: ListTile(
                title: Text(entry.description,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${entry.date} • ${entry.type}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatNaira(entry.amount),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(entry.status,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      );
}

class PayrollPrototypeScreen extends StatelessWidget {
  const PayrollPrototypeScreen({super.key, required this.session});
  final CehSession session;

  @override
  Widget build(BuildContext context) => _PhaseAccountsPage(
        session: session,
        title: 'Payroll',
        children: const [
          AccountsSectionTitle(
            'Payroll foundation',
            subtitle: 'Planned for a later approved phase',
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.badge_outlined, size: 50),
                  SizedBox(height: 12),
                  Text('Not connected yet',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  Text(
                    'Future workflows will distinguish salary advances, site allowances, reimbursements and salary or wage payments.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
