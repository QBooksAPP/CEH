import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = CehSession(
  token: 'test',
  tokenType: 'Bearer',
  expiresAt: '2099-01-01',
  user: CehUser(
    id: 1,
    fullName: 'Admin',
    email: 'admin@example.com',
    role: 'ADMIN',
    isActive: true,
  ),
);

void main() {
  Future<void> pumpReport(
      WidgetTester tester, ReportKind kind, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
            size: size, padding: const EdgeInsets.only(bottom: 24)),
        child: AccountsReportDetailScreen(
          session: _admin,
          api: const CehApiClient(),
          kind: kind,
        ),
      ),
    ));
    await tester.pump();
  }

  for (final kind in [ReportKind.pettyCash, ReportKind.expenses]) {
    testWidgets('${kind.name} filters and actions fit narrow Android width',
        (tester) async {
      await pumpReport(tester, kind, const Size(360, 640));
      expect(tester.takeException(), isNull);

      final from =
          tester.getRect(find.byKey(const ValueKey('report-date-Date from')));
      final to =
          tester.getRect(find.byKey(const ValueKey('report-date-Date to')));
      expect(from.width, greaterThanOrEqualTo(150));
      expect(to.width, greaterThanOrEqualTo(150));
      expect((from.top - to.top).abs(), lessThan(1));

      await tester
          .ensureVisible(find.byKey(const ValueKey('export-report-action')));
      await tester.pumpAndSettle();
      expect(find.text('Run Report'), findsOneWidget);
      expect(find.text('Export Audit Pack'), findsOneWidget);
      final previewTheme = Theme.of(tester.element(find.text('Run Report')));
      expect(previewTheme.colorScheme.primary, CehTheme.ink);
      expect(previewTheme.colorScheme.onPrimary, Colors.white);
      expect(previewTheme.colorScheme.outline, CehTheme.border);
      expect(previewTheme.scaffoldBackgroundColor, CehTheme.background);
      expect(previewTheme.colorScheme.primary, isNot(Colors.purple));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('export-report-action')))
              .bottom,
          lessThanOrEqualTo(616));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('receivables retains usable date and PDF action', (tester) async {
    await pumpReport(tester, ReportKind.receivables, const Size(360, 640));
    expect(find.text('As of date'), findsOneWidget);
    expect(find.text('Invoice date from (optional)'), findsNothing);
    expect(find.text('Select date'), findsOneWidget);
    expect(find.text('Run Report'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(
        Theme.of(tester.element(find.text('Run Report'))).colorScheme.primary,
        CehTheme.ink);
    expect(tester.takeException(), isNull);
  });
}
