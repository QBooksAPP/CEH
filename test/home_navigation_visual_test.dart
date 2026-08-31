import 'dart:io';

import 'package:ceh/core/app_environment.dart';
import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_reports_screen.dart';
import 'package:ceh/screens/module_placeholder_screen.dart';
import 'package:ceh/widgets/ceh_environment_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = CehSession(
  token: 'visual-qa-only',
  tokenType: 'Bearer',
  expiresAt: '2099-01-01',
  user: CehUser(
    id: 1,
    fullName: 'QA Administrator',
    email: 'qa@example.test',
    role: 'ADMIN',
    isActive: true,
  ),
);

Widget _visualApp(Widget page) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CehTheme.light(),
      builder: (context, child) => CehEnvironmentBanner(
        environment: CehAppEnvironment.staging,
        child: child ?? const SizedBox.shrink(),
      ),
      initialRoute: '/page',
      routes: {
        '/': (_) => const Scaffold(
              body: Center(child: Text('CEH Dashboard')),
            ),
        '/page': (_) => page,
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dartExecutable = File(Platform.resolvedExecutable);
    final flutterCache = dartExecutable.parent.parent.parent.parent;
    final font = File(
      '${flutterCache.path}/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    final bytes = await font.readAsBytes();
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
    final icons = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons))))
        .load();
  });

  testWidgets('staging report Home placement visual QA', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_visualApp(const AccountsReportDetailScreen(
      session: _admin,
      api: CehApiClient(),
      kind: ReportKind.pettyCash,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ceh-staging-indicator')), findsOneWidget);
    expect(find.byKey(const ValueKey('ceh-home-action')), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/staging-report-home.png'),
    );
  });

  testWidgets('staging administration Home placement visual QA',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_visualApp(const ModulePlaceholderScreen(
      title: 'Administration',
      message: 'Administration tools remain permission controlled.',
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ceh-home-action')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/staging-administration-home.png'),
    );
  });
}
