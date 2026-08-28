import 'dart:io';

import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/accounts_mock_data.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_home_screen.dart';
import 'package:ceh/screens/accounts/accounts_phase1_screens.dart';
import 'package:ceh/screens/dashboard_screen.dart';
import 'package:ceh/widgets/accounts_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const adminSession = CehSession(
  token: 'test',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 1,
    fullName: 'Admin User',
    email: 'admin@example.test',
    role: 'ADMIN',
    isActive: true,
  ),
);

const operatorSession = CehSession(
  token: 'test',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 2,
    fullName: 'Operator User',
    email: '',
    role: 'OPERATOR',
    isActive: true,
  ),
);

Widget app(Widget home, {bool viewAsOperator = false}) {
  final controller = CehViewModeController();
  if (viewAsOperator) controller.enableOperatorView();
  return CehViewModeScope(
    controller: controller,
    child: MaterialApp(theme: CehTheme.light(), home: home),
  );
}

class MemoryAccountsFiguresPreference implements AccountsFiguresPreference {
  MemoryAccountsFiguresPreference([this.value]);
  bool? value;
  int writes = 0;

  @override
  Future<bool?> read(int userId) async => value;

  @override
  Future<void> write(int userId, bool showFigures) async {
    value = showFigures;
    writes++;
  }
}

class LiveOverviewApi extends CehApiClient {
  const LiveOverviewApi();
  @override
  Future<Map<String, dynamic>> accountsOverview(CehSession session) async => {
        'bank_balance': '1250000.00',
        'petty_cash_outstanding': '175000.00',
        'trade_receivables': '333750.00',
        'expenses_this_month': '230000.00',
      };
}

DashboardScreen dashboard(CehSession session) => DashboardScreen(
      session: session,
      checkForUpdates: false,
      onLogout: () async {},
    );

void main() {
  testWidgets('Accounts is visible to Admin on the company dashboard',
      (tester) async {
    await tester.pumpWidget(app(dashboard(adminSession)));
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets('Accounts is hidden from Operator and Admin View-as-Operator',
      (tester) async {
    await tester.pumpWidget(app(dashboard(operatorSession)));
    expect(find.text('Accounts'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(dashboard(adminSession), viewAsOperator: true));
    expect(find.text('Accounts'), findsNothing);
  });

  testWidgets('Accounts screen independently enforces Admin UI access',
      (tester) async {
    await tester.pumpWidget(app(
        const AccountsHomeScreen(session: operatorSession, liveData: false)));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Financial overview'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(
        const AccountsHomeScreen(session: adminSession, liveData: false),
        viewAsOperator: true));
    expect(find.text('Administrator access required.'), findsOneWidget);
  });

  testWidgets('Accounts dashboard summary cards and all menu areas render',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));

    for (final label in [
      'Cash / Bank',
      'Receivables',
      'Expenses This Month',
      'Net Operating Position',
      'Banking',
      'Billing & Receivables',
      'Expenses',
      'Petty Cash',
      'Payroll',
      'Projects / Job Costing',
      'Equipment Costing',
      'Suppliers',
      'Reports',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('QuickBooks'), findsNothing);
    expect(find.text('Prototype • sample data only'), findsOneWidget);
  });

  testWidgets('Accounts dashboard remains usable at Android phone width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));
    expect(find.text('Cash / Bank'), findsOneWidget);
    final reports = find.byKey(const ValueKey('accounts-menu-reports'));
    await tester.scrollUntilVisible(reports, 300,
        scrollable: find.byType(Scrollable).first);
    expect(reports, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Financial overview is compact on phone without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: false,
      figuresPreference: MemoryAccountsFiguresPreference(true),
    )));
    await tester.pumpAndSettle();

    final cards = find.byType(AccountsSummaryCard);
    expect(cards, findsNWidgets(4));
    expect(tester.getSize(cards.first).height, lessThan(150));
    expect(find.text('Show figures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Financial overview uses four efficient columns when wide',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: false,
      figuresPreference: MemoryAccountsFiguresPreference(true),
    )));
    await tester.pumpAndSettle();

    final cards = find.byType(AccountsSummaryCard);
    final tops =
        List.generate(4, (index) => tester.getTopLeft(cards.at(index)));
    expect(tops.map((point) => point.dy).toSet().length, 1);
    expect(tops.map((point) => point.dx).toSet().length, 4);
    expect(tester.getSize(cards.first).height, lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Show figures masks display but preserves underlying values',
      (tester) async {
    final preference = MemoryAccountsFiguresPreference(true);
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: false,
      figuresPreference: preference,
    )));
    await tester.pumpAndSettle();
    expect(find.text(formatNaira(AccountsMockData.summaries.first.value)),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('accounts-show-figures')));
    await tester.pumpAndSettle();
    expect(find.text('₦••••••'), findsNWidgets(4));
    expect(find.text(formatNaira(AccountsMockData.summaries.first.value)),
        findsNothing);
    final cards = tester
        .widgetList<AccountsSummaryCard>(find.byType(AccountsSummaryCard))
        .toList();
    expect(cards.map((card) => card.value),
        AccountsMockData.summaries.map((summary) => summary.value));
    expect(preference.value, isFalse);
    expect(preference.writes, 1);
  });

  testWidgets('Show figures choice is restored from local preference',
      (tester) async {
    final preference = MemoryAccountsFiguresPreference(false);
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: false,
      figuresPreference: preference,
    )));
    await tester.pumpAndSettle();
    expect(find.text('₦••••••'), findsNWidgets(4));

    await tester.tap(find.byKey(const ValueKey('accounts-show-figures')));
    await tester.pumpAndSettle();
    expect(preference.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: false,
      figuresPreference: preference,
    )));
    await tester.pumpAndSettle();
    expect(find.text(formatNaira(AccountsMockData.summaries.first.value)),
        findsOneWidget);
  });

  testWidgets(
      'live overview removes sample warning and uses authoritative labels',
      (tester) async {
    await tester.pumpWidget(app(AccountsHomeScreen(
      session: adminSession,
      liveData: true,
      api: const LiveOverviewApi(),
      figuresPreference: MemoryAccountsFiguresPreference(false),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Prototype • sample data only'), findsNothing);
    expect(
        find.text('Sample overview figures — not live balances'), findsNothing);
    expect(find.text('Bank Balance'), findsOneWidget);
    expect(find.text('Petty Cash Outstanding'), findsOneWidget);
    expect(find.text('Trade Receivables'), findsOneWidget);
    expect(find.text('Expenses This Month'), findsOneWidget);
    expect(find.text('₦••••••'), findsNWidgets(4));
  });

  testWidgets('navigation opens every Accounts prototype area', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const AccountsHomeScreen(session: adminSession, liveData: false)));

    const destinations = <String, String>{
      'banking': 'Bank accounts',
      'billing-receivables': 'Ready to Invoice',
      'expenses': 'Expense register',
      'petty-cash': 'TOTAL PETTY CASH',
      'payroll': 'Payroll foundation',
      'projects-job-costing': 'Project performance',
      'equipment-costing': 'Equipment profitability',
      'suppliers': 'Supplier directory',
      'reports': 'Management reports',
    };
    for (final entry in destinations.entries) {
      final menu = find.byKey(ValueKey('accounts-menu-${entry.key}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget,
          reason: 'Failed to open ${entry.key}');
      expect(find.text('Prototype • sample data only'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  test('retained prototype fixtures have no backend or QuickBooks dependency',
      () {
    final files = [
      'lib/screens/accounts/accounts_detail_screens.dart',
      'lib/models/accounts_mock_data.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    expect(files, isNot(contains('CehApiClient')));
    expect(files, isNot(contains('package:http')));
    expect(files, isNot(contains('quickbooks.com')));
  });

  test('pending petty cash expense reserves available custodian balance', () {
    final segun = AccountsMockData.pettyCashCustodians
        .singleWhere((item) => item.name == 'Segun');
    expect(segun.balance, 110000);
    expect(segun.pendingApproval, 30000);
    expect(segun.availableBalance, 80000);
    expect(
      AccountsMockData.pettyCashCustodians
          .fold<double>(0, (sum, item) => sum + item.balance),
      175000,
    );
  });

  testWidgets('Banking demonstrates matching and duplicate states',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(app(const BankingPrototypeScreen(session: adminSession)));
    expect(find.text('Zenith Bank'), findsOneWidget);
    expect(find.text('Potential Match'), findsOneWidget);
    expect(find.text('Possible Duplicate'), findsOneWidget);
    final importButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-bank-statement')));
    expect(importButton.onPressed, isNull);
  });

  testWidgets('Petty Cash uses independent custodians and prototype forms',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const PettyCashCustodianPrototypeScreen(session: adminSession)));
    expect(find.byKey(const ValueKey('custodian-felix')), findsOneWidget);
    expect(find.byKey(const ValueKey('custodian-segun')), findsOneWidget);
    expect(find.text('₦175,000.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fund-petty-cash')));
    await tester.pumpAndSettle();
    expect(find.text('Asset transfer'), findsOneWidget);
    expect(find.text('Admin User'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-petty-cash-expense')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('take-receipt-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-receipt-photo')), findsOneWidget);
    await tester.tap(find.text('No Receipt'));
    await tester.pump();
    expect(find.byKey(const ValueKey('no-receipt-reason')), findsOneWidget);
  });
}
