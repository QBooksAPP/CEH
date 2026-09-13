import 'dart:async';

import 'package:ceh/core/app_environment.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/staging_update_installer.dart';
import 'package:ceh/core/update_service.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

const update = CehUpdateInfo(
  buildNumber: 98,
  downloadUrl:
      'https://qbook.concretehireng.com/updates/production/CEH-PRODUCTION-0.4.1-98.apk',
  releaseName: 'CEH 0.4.1',
  environment: 'PRODUCTION',
  applicationId: CehAppEnvironment.productionApplicationId,
  versionName: '0.4.1',
  byteSize: 4,
  sha256: '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
  signingCertificateSha256:
      CehAppEnvironment.productionSigningCertificateSha256,
  filename: 'CEH-PRODUCTION-0.4.1-98.apk',
  releaseNotes: 'Harmless updater acceptance test.',
);

class FixedUpdateService extends CehUpdateService {
  const FixedUpdateService({this.failure});

  final Object? failure;

  @override
  Future<CehUpdateInfo?> checkForUpdate({required int currentBuild}) async {
    if (failure != null) throw failure!;
    return update;
  }
}

class ControlledInstaller extends CehStagingUpdateInstaller {
  ControlledInstaller({this.downloadFailure, this.launchFailure});

  final Object? downloadFailure;
  final Object? launchFailure;
  final downloadGate = Completer<void>();
  final launchGate = Completer<void>();
  bool downloadStarted = false;
  bool launchStarted = false;

  @override
  Future<CehVerifiedStagingUpdate> downloadAndVerify(
    CehUpdateInfo update, {
    required void Function(double progress) onProgress,
  }) async {
    downloadStarted = true;
    onProgress(0.5);
    await downloadGate.future;
    if (downloadFailure != null) throw downloadFailure!;
    return const CehVerifiedStagingUpdate(
      apkPath: 'test.apk',
      metadata: CehApkMetadata(
        applicationId: CehAppEnvironment.productionApplicationId,
        versionName: '0.4.1',
        versionCode: 98,
        environment: 'PRODUCTION',
        signingCertificateSha256:
            CehAppEnvironment.productionSigningCertificateSha256,
      ),
    );
  }

  @override
  Future<CehInstallerLaunchResult> launchInstaller(
    CehVerifiedStagingUpdate update,
  ) async {
    launchStarted = true;
    if (launchFailure != null) throw launchFailure!;
    await launchGate.future;
    return CehInstallerLaunchResult.launched;
  }
}

void main() {
  const session = CehSession(
    token: 'test',
    tokenType: 'Bearer',
    expiresAt: '',
    user: CehUser(
      id: 1,
      fullName: 'Staging Admin',
      email: 'admin@example.test',
      role: 'ADMIN',
      isActive: true,
    ),
  );

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'CEH',
      packageName: CehAppEnvironment.productionApplicationId,
      version: '0.4.0',
      buildNumber: '97',
      buildSignature: 'test',
    );
  });

  Future<void> showDashboard(
    WidgetTester tester,
    ControlledInstaller installer,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: CehViewModeScope(
        controller: CehViewModeController(),
        child: DashboardScreen(
          session: session,
          onLogout: () async {},
          environment: CehAppEnvironment.production,
          updateService: const FixedUpdateService(),
          stagingUpdateInstaller: installer,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Update now'), findsOneWidget);
  }

  testWidgets('busy covers download but clears before installer handoff',
      (tester) async {
    final installer = ControlledInstaller();
    await showDashboard(tester, installer);

    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(installer.downloadStarted, isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    installer.downloadGate.complete();
    await tester.pump();
    await tester.pump();
    expect(installer.launchStarted, isTrue);
    expect(installer.launchGate.isCompleted, isFalse);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Update now'), findsOneWidget);

    installer.launchGate.complete();
    await tester.pump();
  });

  testWidgets('download failure clears busy and reports an error',
      (tester) async {
    final installer = ControlledInstaller(
      downloadFailure:
          const CehUpdateException('Download verification failed.'),
    );
    await showDashboard(tester, installer);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    installer.downloadGate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Download verification failed.'), findsOneWidget);
  });

  testWidgets('installer failure never leaves production disabled',
      (tester) async {
    final installer = ControlledInstaller(
      launchFailure: const CehUpdateException('Installer launch failed.'),
    );
    await showDashboard(tester, installer);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    installer.downloadGate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Installer launch failed.'), findsOneWidget);
  });
}
