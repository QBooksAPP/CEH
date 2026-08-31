import 'dart:io';

import 'package:ceh/core/api_client.dart';
import 'package:ceh/core/app_environment.dart';
import 'package:ceh/core/ceh_theme.dart';
import 'package:ceh/core/session_store.dart';
import 'package:ceh/core/update_service.dart';
import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/mixer_context.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/screens/dashboard_screen.dart';
import 'package:ceh/widgets/ceh_environment_banner.dart';
import 'package:ceh/widgets/mixer_context_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adminSession = CehSession(
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
  const mixer = MixerContext(
    id: 306,
    code: '306',
    name: 'Mixer 306',
    activeAssignments: [
      MixerAssignment(
        clientId: 1,
        clientName: 'Client',
        projectId: 2,
        projectName: 'Project',
        isActive: true,
      ),
    ],
    assignmentHistory: [],
  );

  test('production and staging use only their approved API origins', () {
    expect(
      const CehApiClient(environment: CehAppEnvironment.production).baseUrl,
      CehAppEnvironment.productionApiUrl,
    );
    expect(
      const CehApiClient(environment: CehAppEnvironment.staging).baseUrl,
      CehAppEnvironment.stagingApiUrl,
    );

    expect(
      () => CehAppEnvironment.validate(
        environment: 'production',
        apiBaseUrl: CehAppEnvironment.stagingApiUrl,
        updateChecksEnabled: true,
      ),
      throwsStateError,
    );
    expect(
      () => CehAppEnvironment.validate(
        environment: 'staging',
        apiBaseUrl: CehAppEnvironment.productionApiUrl,
        updateChecksEnabled: false,
      ),
      throwsStateError,
    );
  });

  test('application identities and secure storage namespaces are distinct', () {
    expect(
      CehAppEnvironment.staging.applicationId,
      '${CehAppEnvironment.production.applicationId}.staging',
    );
    expect(
      CehAppEnvironment.production.secureStorageNamespace,
      isNot(CehAppEnvironment.staging.secureStorageNamespace),
    );
    expect(
      SessionStore(environment: CehAppEnvironment.production).sessionKey,
      'ceh_session_v1',
    );
    expect(
      SessionStore(environment: CehAppEnvironment.staging).sessionKey,
      'ceh_staging_session_v1',
    );
    expect(
      SessionStore(environment: CehAppEnvironment.production).sessionKey,
      isNot(SessionStore(environment: CehAppEnvironment.staging).sessionKey),
    );
  });

  test('staging disables updates while production behavior remains enabled',
      () {
    expect(
      const CehUpdateService(environment: CehAppEnvironment.production)
          .updateChecksEnabled,
      isTrue,
    );
    expect(
      const CehUpdateService(environment: CehAppEnvironment.staging)
          .updateChecksEnabled,
      isFalse,
    );
    expect(
      () => CehAppEnvironment.validate(
        environment: 'staging',
        apiBaseUrl: CehAppEnvironment.stagingApiUrl,
        updateChecksEnabled: true,
      ),
      throwsStateError,
    );
  });

  test('staging update check exits without contacting production releases',
      () async {
    final result = await const CehUpdateService(
      environment: CehAppEnvironment.staging,
    ).checkForUpdate(currentBuild: 96);

    expect(result, isNull);
  });

  testWidgets('STAGING identification renders only for staging',
      (tester) async {
    Widget app(CehAppEnvironment environment) => MaterialApp(
          theme: CehTheme.light(),
          home: CehEnvironmentBanner(
            environment: environment,
            child: const Scaffold(body: Text('CEH app')),
          ),
        );

    await tester.pumpWidget(app(CehAppEnvironment.production));
    expect(find.byKey(const ValueKey('ceh-staging-indicator')), findsNothing);

    await tester.pumpWidget(app(CehAppEnvironment.staging));
    expect(find.byKey(const ValueKey('ceh-staging-indicator')), findsOneWidget);
    expect(find.text('STAGING'), findsOneWidget);

    final indicator = tester.widget<Text>(find.text('STAGING'));
    expect(indicator.style?.color, Colors.white);
    final material = tester.widget<Material>(
      find.ancestor(of: find.text('STAGING'), matching: find.byType(Material)),
    );
    expect(material.color, CehTheme.ink);
  });

  testWidgets('staging dashboard welcome card uses light CEH surfaces',
      (tester) async {
    final viewMode = CehViewModeController();
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: CehViewModeScope(
        controller: viewMode,
        child: DashboardScreen(
          session: adminSession,
          onLogout: () async {},
          checkForUpdates: false,
          environment: CehAppEnvironment.staging,
        ),
      ),
    ));
    await tester.pump();

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('dashboard-welcome-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.gradient, isNull);
    expect(decoration.border, isNotNull);

    final welcome = tester.widget<Text>(find.textContaining('Welcome'));
    expect(welcome.style?.color, CehTheme.text);
  });

  testWidgets('production dashboard welcome styling remains unchanged',
      (tester) async {
    final viewMode = CehViewModeController();
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: CehViewModeScope(
        controller: viewMode,
        child: DashboardScreen(
          session: adminSession,
          onLogout: () async {},
          checkForUpdates: false,
          environment: CehAppEnvironment.production,
        ),
      ),
    ));
    await tester.pump();

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('dashboard-welcome-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.gradient, isA<LinearGradient>());
    expect(decoration.border, isNull);
  });

  testWidgets('staging mixer header uses light CEH surfaces', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: CehTheme.light(),
      home: const Scaffold(
        body: MixerContextHeader(
          context: mixer,
          environment: CehAppEnvironment.staging,
        ),
      ),
    ));

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('mixer-context-header-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border, isNotNull);
    expect(find.text('MIXER 306'), findsOneWidget);
    expect(find.text('Client • Project'), findsOneWidget);
  });

  test('Android flavor configuration preserves production and isolates staging',
      () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final productionLabel =
        File('android/app/src/production/res/values/strings.xml')
            .readAsStringSync();
    final stagingLabel = File('android/app/src/staging/res/values/strings.xml')
        .readAsStringSync();

    expect(gradle, contains('applicationId = "com.concreteequipmenthire.ceh"'));
    expect(gradle, contains('create("production")'));
    expect(gradle, contains('create("staging")'));
    expect(gradle, contains('applicationIdSuffix = ".staging"'));
    expect(
        gradle, contains('Staging flavor requires CEH_ENVIRONMENT=staging.'));
    expect(
      gradle,
      contains('Production flavor cannot use a staging environment define.'),
    );
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(productionLabel, contains('>CEH</string>'));
    expect(stagingLabel, contains('>CEH STAGING</string>'));
  });
}
