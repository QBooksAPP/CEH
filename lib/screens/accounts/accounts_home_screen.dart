import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/internal_navigation.dart';
import '../../core/view_mode.dart';
import '../../models/accounts_mock_data.dart';
import '../../models/session.dart';
import '../../widgets/accounts_widgets.dart';
import 'accounts_detail_screens.dart';
import 'accounts_live_screens.dart';
import 'accounts_phase1_screens.dart';
import 'accounts_billing_screen.dart';

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
  });
  final CehSession session;
  final bool liveData;
  final AccountsFiguresPreference? figuresPreference;

  @override
  State<AccountsHomeScreen> createState() => _AccountsHomeScreenState();
}

class _AccountsHomeScreenState extends State<AccountsHomeScreen> {
  late final AccountsFiguresPreference _figuresPreference;
  bool _showFigures = true;

  @override
  void initState() {
    super.initState();
    _figuresPreference =
        widget.figuresPreference ?? const DeviceAccountsFiguresPreference();
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
          'Mixer and equipment profitability',
          Icons.precision_manufacturing_outlined,
          EquipmentCostingPrototypeScreen(session: session)),
      _AccountsDestination(
          'Suppliers',
          'Supplier directory and spend',
          Icons.local_shipping_outlined,
          SuppliersPrototypeScreen(session: session)),
      _AccountsDestination('Reports', 'Management reporting workspace',
          Icons.bar_chart_outlined, ReportsPrototypeScreen(session: session)),
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
          const PrototypeBanner(),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: AccountsSectionTitle('Financial overview',
                  subtitle: 'Sample overview figures — not live balances'),
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
