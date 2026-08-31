import 'dart:async';
import 'dart:typed_data';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/accounts/accounts_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = CehSession(
  token: 'staging-test-token',
  tokenType: 'Bearer',
  expiresAt: '2099-01-01',
  user: CehUser(
    id: 1,
    fullName: 'Staging Admin',
    email: 'staging@example.com',
    role: 'ADMIN',
    isActive: true,
  ),
);

final _pdf = ProductionReportFile(
  bytes: Uint8List.fromList('%PDF-test'.codeUnits),
  filename: 'Petty-Cash-Report.pdf',
);

class _ReportApi extends CehApiClient {
  _ReportApi(this.download);

  final Future<ProductionReportFile> Function() download;

  @override
  Future<ProductionReportFile> accountsReportPdf(CehSession session,
          {required String endpoint,
          required String filename,
          Map<String, String> filters = const {}}) =>
      download();
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required CehApiClient api,
    required ReportFileWriter writer,
    required ReportFileSharer sharer,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: AccountsReportDetailScreen(
        session: _session,
        api: api,
        kind: ReportKind.pettyCash,
        writeReportFile: writer,
        shareReportFile: sharer,
      ),
    ));
    await tester
        .ensureVisible(find.byKey(const ValueKey('export-report-action')));
    await tester.pumpAndSettle();
  }

  Future<void> tapExport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('export-report-action')));
    await tester.pump();
  }

  testWidgets('busy covers download and file write but clears before share',
      (tester) async {
    final download = Completer<ProductionReportFile>();
    final write = Completer<String>();
    final share = Completer<void>();
    var shareCalled = false;
    await pumpScreen(tester,
        api: _ReportApi(() => download.future),
        writer: (_) => write.future,
        sharer: (_, __) {
          shareCalled = true;
          return share.future;
        });

    await tapExport(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('export-report-action')))
            .onPressed,
        isNull);

    download.complete(_pdf);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(shareCalled, isFalse);

    write.complete('/temporary/Petty-Cash-Report.pdf');
    await tester.pump();
    expect(shareCalled, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('export-report-action')))
            .onPressed,
        isNotNull);

    share.complete();
    await tester.pump();
  });

  testWidgets('download failure clears busy and reports export error',
      (tester) async {
    await pumpScreen(tester,
        api: _ReportApi(() async => throw Exception('download failed')),
        writer: (_) async => '/unused',
        sharer: (_, __) async {});

    await tapExport(tester);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        find.textContaining(
            'Unable to export report: Exception: download failed'),
        findsOneWidget);
  });

  testWidgets('file write failure clears busy and reports export error',
      (tester) async {
    await pumpScreen(tester,
        api: _ReportApi(() async => _pdf),
        writer: (_) async => throw Exception('write failed'),
        sharer: (_, __) async {});

    await tapExport(tester);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        find.textContaining('Unable to export report: Exception: write failed'),
        findsOneWidget);
  });

  testWidgets('external share failure leaves screen enabled and reports error',
      (tester) async {
    await pumpScreen(tester,
        api: _ReportApi(() async => _pdf),
        writer: (_) async => '/temporary/Petty-Cash-Report.pdf',
        sharer: (_, __) async => throw Exception('viewer failed'));

    await tapExport(tester);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('export-report-action')))
            .onPressed,
        isNotNull);
    expect(
        find.textContaining('Unable to open report: Exception: viewer failed'),
        findsOneWidget);
  });

  testWidgets('successful export preserves file path and report subject',
      (tester) async {
    String? sharedPath;
    String? sharedSubject;
    await pumpScreen(tester, api: _ReportApi(() async => _pdf),
        writer: (file) async {
      expect(file, same(_pdf));
      return '/temporary/${file.filename}';
    }, sharer: (path, subject) async {
      sharedPath = path;
      sharedSubject = subject;
    });

    await tapExport(tester);
    await tester.pump();
    expect(sharedPath, '/temporary/Petty-Cash-Report.pdf');
    expect(sharedSubject, 'Petty Cash Report');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Unable to'), findsNothing);
  });
}
