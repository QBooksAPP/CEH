# Production updater transition (local preparation only)

Candidate: production 0.4.0 / 97, package com.concreteequipmenthire.ceh.
No endpoint, artifact or release is published by this change.

## Channel

97 uses https://qbook.concretehireng.com/updates/production/manifest.json
for 98 and later. This path is intended for the NEW Production VPS after
separately approved cutover. It is not a staging API or an accounting endpoint.
Missing/unavailable/invalid manifests report failure; there is no GitHub or
staging fallback. The existing installed build-96 binary remains unchanged.

Schema version 1 matches the secure staging format, with channel=production,
environment=PRODUCTION, applicationId=com.concreteequipmenthire.ceh,
versionName, integer versionCode>=98, build, 40-character source commit,
publishedAt and optional releaseNotes. apk contains filename, url, byteSize,
sha256 and signingCertificateSha256. Production filenames must match
CEH-PRODUCTION-[0-9A-Za-z._-]+.apk. URLs must be HTTPS on the exact hostname,
port 443 and /updates/production/<filename>, with no credentials/query/fragment
or redirects. Manifest size is capped at 64 KiB; APK size at 250 MiB.

Signer pin: F8:59:04:5A:BA:78:42:41:FD:33:F6:DF:18:2A:48:4D:71:60:12:35:0A:C9:DE:64:C8:8C:97:99:CB:79:A3:0E.
Download checks length, SHA-256, native package/version/environment/signer.
Android rechecks package, current signer and increasing version before invoking
the installer. Production and staging use separate bridge names, private cache
directories, provider authorities and pinned identities. No GitHub credential
is embedded. Busy state ends before external installer/permission handoff.

## Future VPS publication design — not executed

Use a dedicated root-controlled static update directory outside API/evidence
and application releases, e.g. /var/www/ceh-production-updates/releases/.
Publish immutable uniquely named APKs first, verify downloaded bytes/signature,
then atomically activate manifest.json. Dedicated publisher permissions must
not grant PHP-FPM write access. Nginx serves only approved JSON/APK files,
disables indexes and script execution; HTTPS certificate must cover qbook.
Manifest: Cache-Control no-store. Uniquely named APKs: immutable caching.
No accounting credentials or protected evidence are served from this tree.
Keep prior manifests/APKs and an artifact hash inventory for recovery. Removing
an erroneous offer is possible; installed Android downgrades are not promised.
Test real TLS, headers, byte/hash fidelity and failure handling before offering
an update. DNS/vhost/firewall changes require separate approval.

## Transition and privacy gates

1. Privately build/review signed 97 from an exact approved source checkpoint.
2. Separately authorize public GitHub build-97 release with the legacy CEH.apk
   asset/tag expected by installed build-96. Never remove discovery prematurely.
3. Verify installed-base migration to 97 and HTTPS readiness.
4. Only then consider making the existing repository private.

The candidate Actions workflow remains manual, exact-SHA, explicit-confirmation,
contents:read, private-repository-only, environment production-android, and
artifact-only. The helper independently repeats the event/private/SHA gates.
There are no release, updater, SSH or deployment steps.

Current PUBLIC repository cannot satisfy the private-artifact guard. Making it
private before transition would break build-96 discovery. Therefore execution
is BLOCKED pending approval of a private build execution arrangement (or an
explicitly approved local private signing process); do not remove the guard.
Environment/reviewer capability and signing-secret scoping must be verified
before execution. No repository/settings change is authorized by this document.
All application fixes must be reviewed/checkpointed separately from Web source.
The candidate must then pass signer/package/version checks and physical-device
installation/updater acceptance; these are not proven by local Dart tests.

## Local change inventory and validation

- lib/core/app_environment.dart
- lib/core/update_service.dart
- lib/core/staging_update_installer.dart (shared verified-download implementation;
  legacy class/file names retained for existing staging callers)
- lib/screens/dashboard_screen.dart
- android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt
- android/app/src/production/AndroidManifest.xml
- android/app/src/production/res/xml/ceh_production_update_paths.xml
- test/app_environment_test.dart
- test/staging_update_service_test.dart
- test/production_banking_native_test.dart
- test/production_update_test.dart
- test/production_update_dashboard_test.dart
- tools/production_candidate.py
- Server/PRODUCTION_UPDATER_TRANSITION.md

The already prepared production-candidate.yml remains uncommitted/manual-only;
the production publication workflow was not changed in this task. Existing Web
and other candidate changes remain separate and uncommitted.

Latest local validation: 535 complete Flutter tests passed; 60 focused updater/native
contract/environment tests and a separate staging-selection test passed; flutter analyze clean. Candidate
helper Python syntax passed; mocked helper tests rejected public repository,
missing confirmation and wrong SHA before any build. Native installer/device
execution and signed APK inspection remain pending the explicitly approved
candidate build; no APK was built during this task.

Flavour-specific trust-source correction and the compiled-APK inspection gate
are documented in PRODUCTION_CANDIDATE_SOURCE_REVIEW.md, including the exact
candidate file list, five passing inspector regressions and remaining gates.
