# Phase 6B.2 — Mobile statement upload and explicit import

ADMIN-only Banking → selected bank → Import Statement. Android's system document
picker grants access only to the chosen file, with no broad storage permission.
CSV/XLSX bytes are bounded to 10 MB. The picker does not own the screen's busy
state. Network work has a timeout and clears busy state on all exits.

Authenticated multipart upload retains the existing immutable document lifecycle.
Preview reads server totals, reconciliation, invalid/overlap reasons and the exact
server-issued confirmation SHA-256. Upload never confirms automatically. A failed
or uncertain confirmation requires reloading the preview; an already committed
document shows its existing batch rather than offering another import.

Repeated legitimate fees are never shown as duplicate warnings. The backend
summary additions are descriptive only; import locking/idempotency/accounting
rules are unchanged. No reconciliation, expense, payment or refund actions added.

## Validation

- Full Flutter suite: 469 passed; analyze: no issues.
- Disposable MySQL import lifecycle: 30 checks passed, database removed.
- Pure parser regressions: 41 passed.
- QA workbook parsed locally, never imported by the agent.

## Controlled QA

File: CEH-STAGING-QA-Zenith-96011.xlsx (3,940 bytes)
SHA-256: 7fe7eecabc5628207f3df876733f1cbca1edb658c9d90c1565fb5176776a28fc

Four transactions: credit 500.00; debits 53.75, 53.75, 100.00.
Opening 1000.00; closing 1292.50. The charge rows have identical date,
narration/reference/amount, distinct physical rows 3/4 and occurrences 1/2.
The user alone uploads/confirms on staging. Preserve retained batch 2.

The root-only staging verification record stores complete pre-test table
hashes/counts and a cleanup plan resolving this exact file SHA-256 + bank 1.
After phone QA, resolve document/batch IDs and dependent row/audit IDs; verify
unrelated rows against that baseline before any separately approved cleanup.
No auto-increment reset. No cleanup or import is performed during deployment.

Deploy only bank_import_common.php through an immutable release, preserving the
previous public target, then graceful php8.3-fpm reload and authenticated read
verification before updater publication. Production remains untouched.

## Staging delivery

96011 / 0.3.0-staging.11: 59,843,861-byte APK, permanent staging signer verified.
APK SHA-256: aabc8d1e7b1695a736aa72d29439fd53801e2934056d20996f0c01a96cb46f07
Active release: build-96-banking-96011-20260910T130840Z.
Administrator reload and authenticated verifier passed: all table hashes unchanged,
719 retained transactions, 28 journals / 66 lines. Health 200; unauthenticated
upload/preview/confirm 401. Pre-QA hashes and cleanup scope are recorded in
/var/www/ceh-staging/private/banking-96011-verification.
The QA workbook has NOT been uploaded or confirmed by the agent.

## Phone acceptance and controlled cleanup

User acceptance passed on 96011: Import 3 retained all four rows, including both
53.75 charges. The administrator ran the guarded cleanup after full pre-QA hash
comparison excluding only the verified fixture. Removed statement rows 722–725,
batch 3, document 2, audit events 152–153. All pre-QA hashes restored; retained
batch 2 has 719 rows; journals 28 / lines 66. Auto-increments were not reset.
Recovery: private/banking-96011-verification/cleanup-recovery.json on staging.

The Import Details bank label is corrected locally for this checkpoint, with a
widget regression. No replacement APK was requested for this cosmetic change;
the currently published 96011 remains the accepted binary.
