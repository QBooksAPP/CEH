# Production 0.4.0 / 97 candidate source review

Status: LOCAL REVIEW ONLY. No commit, push, APK build, repository creation or settings change.
Validation: 535 complete Flutter tests passed; flutter analyze reported no
issues. The focused updater/environment/native-contract run passed 60 tests;
the separate staging-defined selection test passed. Five Python inspector
tests passed, including 40 opposite-pin flavour/payload/encoding combinations.
These tests do not certify a compiled candidate APK, which remains unbuilt.
Base authoritative checkpoint: 6dea17843fda870a278ff6a313270f08b07838e2.
Candidate source commit SHA and Git tree: NOT ASSIGNED (requires separate approval).
Private build-control repository SHA: NOT ASSIGNED (repository not created).
These are distinct identities; the later private build must verify an approved
CEH source SHA, tree and deterministic tracked-file manifest independently of
its own reviewed build-control SHA.

## Binary isolation correction

Android selects exactly one UpdateTrust.kt through production/staging source
sets. Common MainActivity has no signing pins or opposite-flavour package/channel
selection and retains package, environment, increasing-version and certificate
checks. Dart selects its environment using a compile-time constant; shared
transport derives its host/path/pin from that selected environment, not literal
branches containing both hosts. Production-only configuration is expected to be
AOT tree-shaken; this expectation is NOT recorded as compiled-artifact proof.

The read-only APK inspector decompresses and scans every ZIP entry, including
DEX, resources, assets and all native libraries. It rejects opposite-flavour
package/channel/provider/cache/host/pin values, checks UTF-8/UTF-16 and raw digest
representations, and requires observable selected pin/manifest plus DEX/AOT
payloads. The signing helper invokes inspection BEFORE preparing any upload
artifact, in addition to actual signer/package/version/non-debuggable/provider
checks. Synthetic inspector tests are not a compiled candidate APK test.

No candidate APK has been built. Binary isolation acceptance remains PENDING
that separately authorized compiled-artifact inspection. No version-97 source
SHA can yet be certified as binary-isolated.

## Candidate-only GitHub fallback removal

Under explicit candidate-97-only approval, the residual productionGithub enum
and UI external-launch fallback have been removed. Both flavours use the
verified HTTPS installer; there is no operational GitHub updater fallback in
candidate source. A regression checks the channel enum and UI/service paths.
The preserved build-96 APK still hashes to
00556CAADBF7484CA6876519BD2652B4C0FAC9E3A0E8D6127356EE208DD1E085;
the public publication workflow is unchanged. Installed build-96 is not rebuilt.

Proposed commit message (NOT executed):
Prepare production 0.4.0+97 candidate with isolated HTTPS updates [skip ci]

Required transition remains: installed build-96 discovers public GitHub release
97; production-signed 97 installs; 97 and later use CEH HTTPS for subsequent
updates. Do not hide the public release channel before transition verification.

## Exact proposed delta from the base checkpoint

- .github/workflows/production-candidate.yml
- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/concreteequipmenthire/ceh/MainActivity.kt
- android/app/src/main/res/xml/ceh_bank_document_paths.xml
- android/app/src/production/AndroidManifest.xml
- android/app/src/production/kotlin/com/concreteequipmenthire/ceh/UpdateTrust.kt
- android/app/src/production/res/xml/ceh_production_update_paths.xml
- android/app/src/staging/AndroidManifest.xml
- android/app/src/staging/kotlin/com/concreteequipmenthire/ceh/UpdateTrust.kt
- android/app/src/staging/res/xml/ceh_bank_document_paths.xml — DELETE; relocated to main for both Banking flavours
- lib/core/api_client.dart
- lib/core/app_environment.dart
- lib/core/staging_update_installer.dart
- lib/core/update_service.dart
- lib/models/accounts.dart
- lib/screens/accounts/accounts_billing_screen.dart
- lib/screens/accounts/accounts_estimates_screen.dart
- lib/screens/accounts/legacy_payment_review_screen.dart
- lib/screens/dashboard_screen.dart
- Server/customer_payment_draft_state.php
- Server/customer_payment_post_common.php
- Server/customer_payment_review_common.php
- Server/customer_payment_review.php
- Server/customer_receipt_save.php
- Server/LEGACY_INVOICE_DOCUMENT_POLICY.md
- Server/PRODUCTION_UPDATER_TRANSITION.md
- test/apk_trust_isolation_test.py
- test/app_environment_test.dart
- test/compiled_update_trust_test.dart
- test/legacy_invoice_document_test.dart
- test/legacy_payment_clone_test.php
- test/legacy_payment_review_test.dart
- test/legacy_payment_state_test.php
- test/production_banking_native_test.dart
- test/production_candidate_workflow_test.dart
- test/production_update_dashboard_test.dart
- test/production_update_test.dart
- test/refund_linkage_mysql_test.php
- test/staging_update_android_contract_test.dart
- test/staging_update_service_test.dart
- tools/apk_trust_isolation.py
- tools/production_candidate.py
- Server/PRODUCTION_CANDIDATE_SOURCE_REVIEW.md — this review

The production-candidate workflow/helper/regression files are build-control
preparation, separately identifiable from application/backend changes; the
private-repository SHA handoff still needs its approved adaptation. Build version
0.4.0 / 97 is explicitly supplied by the candidate helper, not inferred from a
workflow run number. The existing Accounts/Banking checkpoint is inherited via
base history, not manually recopied.

## Explicit exclusions

Web/**, Server/web_register.php, Server/web_register_common.php,
Server/web_session.php, .github/workflows/web-checks.yml and the Web-only
.gitignore delta are excluded. Generated Python caches, APKs, signing materials,
credentials, recovery records and publication artifacts are excluded.

## Private build design preserved

Exact ephemeral public-source Git checkout; approved source SHA/tree/file
manifest; validation before signing; independent signing-job source validation;
private artifact only, seven-day retention; no Releases, updater publication,
SSH/SCP or server deployment. Public-repository guard remains enabled. Account
plan/environment and branch protections are unverified: no capabilities assumed.
Existing signing secrets remain untouched; future private environment values
are to be entered manually by the owner, never copied via Actions.
