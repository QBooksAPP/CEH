import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/internal_navigation.dart';
import '../../core/api_client.dart';
import '../../core/view_mode.dart';
import '../../models/accounts_mock_data.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';
import 'accounts_detail_screens.dart';
import 'accounts_live_screens.dart';
import 'accounts_phase1_screens.dart';
import 'accounts_billing_screen.dart';
import 'accounts_reports_screen.dart';

abstract interface class AccountsFiguresPreference {
  Future<bool?> read(int userId);
  Future<void> write(int userId, bool showFigures);
}

class DeviceAccountsFiguresPreference implements AccountsFiguresPreference {
  const DeviceAccountsFiguresPreference();
  static const _storage = FlutterSecureStorage();

  String _key(int userId) => 'accounts_show_figures_$userId';

  @override
  Future<bool?> read(int userId) async {
    final value = await _storage.read(key: _key(userId));
    return switch (value) { 'true' => true, 'false' => false, _ => null };
  }

  @override
  Future<void> write(int userId, bool showFigures) =>
      _storage.write(key: _key(userId), value: '$showFigures');
}

class AccountsHomeScreen extends StatefulWidget {
  const AccountsHomeScreen({
    super.key,
    required this.session,
    this.liveData = true,
    this.figuresPreference,
    this.api = const CehApiClient(),
  });
  final CehSession session;
  final bool liveData;
  final AccountsFiguresPreference? figuresPreference;
  final CehApiClient api;

  @override
  State<AccountsHomeScreen> createState() => _AccountsHomeScreenState();
}

class _AccountsHomeScreenState extends State<AccountsHomeScreen> {
  late final AccountsFiguresPreference _figuresPreference;
  bool _showFigures = true;
  Future<Map<String, dynamic>>? _overview;

  @override
  void initState() {
    super.initState();
    _figuresPreference =
        widget.figuresPreference ?? const DeviceAccountsFiguresPreference();
    if (widget.liveData) {
      _overview = widget.api.accountsOverview(widget.session);
    }
    _restoreFiguresPreference();
  }

  Future<void> _restoreFiguresPreference() async {
    try {
      final stored = await _figuresPreference.read(widget.session.user.id);
      if (stored != null && mounted) setState(() => _showFigures = stored);
    } catch (_) {
      // A display preference must never block Accounts access.
    }
  }

  Future<void> _setShowFigures(bool value) async {
    setState(() => _showFigures = value);
    try {
      await _figuresPreference.write(widget.session.user.id, value);
    } catch (_) {
      // Keep the in-memory privacy choice when device storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final liveData = widget.liveData;
    if (!isUiAdmin(context, session)) {
      return const Scaffold(
          body: Center(child: Text('Administrator access required.')));
    }
    final destinations = <_AccountsDestination>[
      _AccountsDestination(
          'Banking',
          'Balances, statements and reconciliation',
          Icons.account_balance_outlined,
          liveData
              ? AccountsBankingScreen(session: session)
              : BankingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Billing & Receivables',
          'Production reports and client balances',
          Icons.receipt_long_outlined,
          liveData
              ? AccountsBillingScreen(session: session)
              : BillingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Expenses',
          'Operating costs and receipts',
          Icons.payments_outlined,
          liveData
              ? AccountsExpensesScreen(session: session)
              : ExpensesPrototypeScreen(session: session)),
      _AccountsDestination(
          'Petty Cash',
          'Independent custodian balances',
          Icons.account_balance_wallet_outlined,
          liveData
              ? AccountsPettyCashScreen(session: session)
              : PettyCashCustodianPrototypeScreen(session: session)),
      _AccountsDestination('Payroll', 'Future payroll and staff payments',
          Icons.badge_outlined, PayrollPrototypeScreen(session: session)),
      _AccountsDestination(
          'Projects / Job Costing',
          'Production and project contribution',
          Icons.business_center_outlined,
          ProjectCostingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Equipment Costing',
          'Mixer and equipment contribution',
          Icons.precision_manufacturing_outlined,
          EquipmentCostingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Suppliers',
          'Supplier directory and spend',
          Icons.local_shipping_outlined,
          SuppliersPrototypeScreen(session: session)),
      _AccountsDestination(
          'Reports',
          'Live financial reports and audit exports',
          Icons.bar_chart_outlined,
          liveData
              ? AccountsReportsScreen(session: session, api: widget.api)
              : ReportsPrototypeScreen(session: session)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: cehHomeAction(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (!liveData) ...[
            const PrototypeBanner(),
            const SizedBox(height: 18)
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: AccountsSectionTitle('Financial overview',
                  subtitle: liveData
                      ? 'Authoritative ledger and Accounts balances'
                      : 'Sample overview figures — not live balances'),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: 'Show figures',
              toggled: _showFigures,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Show figures',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Switch(
                  key: const ValueKey('accounts-show-figures'),
                  value: _showFigures,
                  onChanged: _setShowFigures,
                ),
              ]),
            ),
          ]),
          if (liveData)
            FutureBuilder<Map<String, dynamic>>(
              future: _overview,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              'Live financial overview unavailable: ${snapshot.error ?? 'No data'}')));
                }
                final o = snapshot.data!;
                final values = [
                  (
                    'Bank Balance',
                    o['bank_balance'],
                    'Posted bank ledger balance'
                  ),
                  (
                    'Petty Cash Outstanding',
                    o['petty_cash_outstanding'],
                    'Current effective custodian balance'
                  ),
                  (
                    'Trade Receivables',
                    o['trade_receivables'],
                    'Effective issued-invoice outstanding'
                  ),
                  (
                    'Expenses This Month',
                    o['expenses_this_month'],
                    'Posted expenses • document date'
                  ),
                ];
                return AccountsResponsiveGrid(
                  mobileColumns: 1,
                  tabletColumns: 2,
                  desktopColumns: 4,
                  mobileChildAspectRatio: 2.8,
                  tabletChildAspectRatio: 2.6,
                  desktopChildAspectRatio: 2.15,
                  children: [
                    for (var i = 0; i < values.length; i++)
                      AccountsSummaryCard(
                        label: values[i].$1,
                        value: double.tryParse('${values[i].$2}') ?? 0,
                        detail: values[i].$3,
                        showValue: _showFigures,
                        compact: true,
                        emphasized: false,
                        icon: const [
                          Icons.account_balance_outlined,
                          Icons.account_balance_wallet_outlined,
                          Icons.request_quote_outlined,
                          Icons.trending_down,
                        ][i],
                      ),
                  ],
                );
              },
            )
          else
            AccountsResponsiveGrid(
              mobileColumns: 1,
              tabletColumns: 2,
              desktopColumns: 4,
              mobileChildAspectRatio: 2.8,
              tabletChildAspectRatio: 2.6,
              desktopChildAspectRatio: 2.15,
              children: [
                for (var i = 0; i < AccountsMockData.summaries.length; i++)
                  AccountsSummaryCard(
                    label: AccountsMockData.summaries[i].label,
                    value: AccountsMockData.summaries[i].value,
                    detail: AccountsMockData.summaries[i].detail,
                    showValue: _showFigures,
                    compact: true,
                    emphasized: i == AccountsMockData.summaries.length - 1,
                    icon: const [
                      Icons.account_balance_outlined,
                      Icons.request_quote_outlined,
                      Icons.trending_down,
                      Icons.trending_up,
                    ][i],
                  ),
              ],
            ),
          const SizedBox(height: 24),
          const AccountsSectionTitle('Management areas'),
          AccountsResponsiveGrid(
            tabletColumns: 2,
            desktopColumns: 3,
            childAspectRatio: 2.15,
            children: [
              for (final destination in destinations)
                AccountsMenuCard(
                  key: ValueKey(
                      'accounts-menu-${destination.title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-').replaceAll(RegExp(r'-$'), '')}'),
                  title: destination.title,
                  subtitle: destination.subtitle,
                  icon: destination.icon,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => destination.screen)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountsDestination {
  const _AccountsDestination(this.title, this.subtitle, this.icon, this.screen);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget screen;
}
