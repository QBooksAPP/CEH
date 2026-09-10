# Phase 6B.3 — phone acceptance approved; QA fixture cleaned

Checkpoint: 9398c18b8701e22dd08bdac78ad0e47d5fb204d0.
Production and retained Zenith batch 2 must not be modified.

## Ownership contract

Statement row locks precede source expense locks. Statement-derived expense
update/review resolves the immutable source identity outside the transaction,
then locks/revalidates it. Reconciliation locks both sides and validates the
posted journal. A successful same-pair retry returns its existing match.

Banking-only ownership transactions use READ COMMITTED plus explicit row locks.
This avoids missing-owner next-key gap locks in competing source claims.
Deadlock/lock-timeout retries replay only fully rolled-back database work, with
at most three attempts; exhaustion returns an authoritative-refresh conflict.
No external effects belong in these callbacks.

## Migration v1.24 preflight (completed; retained for deployment records)

1. Verify DATABASE() is exactly ceh_staging and all affected tables are InnoDB.
2. Record schema, row counts, complete deterministic data hashes and a protected
   dump of general expenses, statement rows, matches, refunds, journals/lines
   and financial audit. Record batch 2's 719-row hash separately.
3. Assert active_statement_row_id is absent and
   uq_general_expense_statement_source is the current unique index.
4. Reject any CANCELLED_NOT_SPENT expense with a journal, bank match or refund;
   reject inconsistent source bank/date/amount/reference or multiple active owners.
5. Apply migration_v1_24_bank_expense_reservation.sql once. DDL is not transactional.
6. Verify original columns/hashes unchanged. Generated active identity is NULL
   only for unposted cancelled expenses. All other source identities remain
   uniquely reserved. The original created_from_statement_row_id is never erased.

## Guarded rollback

First disable/revert the new Banking actions. Before restoring the old unique
index, assert no non-NULL created_from_statement_row_id occurs more than once
across ALL expenses, including cancelled history. If any row has been reused,
STOP: the old schema cannot represent the preserved history. Never delete or
detach history merely to force rollback.

Only when that guard passes, add the old unique index first, then drop the new
unique index and generated column. Keep the normal history index if needed by
the foreign key. Verify all original data hashes. Do not reset sequences.

## Validation and staging delivery

Read-only staging preflight supplied by administrator: ceh_staging, generated
column absent, old statement-source unique index present; 2 draft expenses,
5 approved expenses with journals, no statement-derived expenses. Retained
batch 2 has 719 rows; journal baseline is 28 / 66. This is not a migration
backup or authorization to skip the remaining data-hash compatibility checks.

Local disposable Banking regression currently passes 62 checks, including
confirmation-time bank, amount, direction, date and reference rejection,
concurrent source ownership, cancelled reservation reuse and no-journal matching.
Focused transaction-detail widget tests pass (5 tests).

Final local validation: 475 Flutter tests pass; analyzer has no issues.
The actual HTTP Expense lifecycle test passes 28 checks, including two-server
simultaneous approval (one success, one safe rejection, one balanced journal).
Refund integration/concurrency passes 28 checks; Banking passes 62 checks.
All disposable databases/users and temporary endpoint files were removed.

Staging migration v1.24 preserved all ten original table hashes and the
719-row Batch 2 / 28-journal / 66-line baseline. Immutable release:
`build-96-banking-96012-20260910T165200Z`; administrator confirmed the graceful
FPM reload and authenticated read-only verifier passed with all hashes unchanged.

Signed APK: 0.3.0-staging.12 / 96012, 60,056,853 bytes.
SHA-256: `c898bcd07feeb515a3d8fcf96917201ea7f667021bb5a7b02df54829d848cce4`.
Permanent staging signer verified; no commit/push performed.

Controlled QA: A row 726 (-1000) is unclaimed; B row 727 (-2000) has eligible
approved Expense CEH-EX-000008; C row 728 (+500) has approved original Expense
CEH-EX-000009 (1000). B/C prerequisite journals are 37/38. Preparation baseline
is now 30 journals / 70 lines; no matching/refund/A-creation acceptance action
was performed. All original records and Batch 2 remain unchanged.
Protected cleanup record:
`/var/www/ceh-staging/private/banking-96012-qa/fixture-record.json`.

## Completed phone acceptance

- A: create, submit and approve Expense; one new balanced journal and ownership.
- B: match CEH-EX-000008; no additional journal.
- C: link refund to CEH-EX-000009; no journal; partial refund remains 500.
- Verify history/navigation on the physical phone, then separately authorize cleanup.

All three scenarios passed physical-phone acceptance. Scenario A created Expense
CEH-EX-000010 and journal 39 (1000 debit/credit, two lines). B matched Expense 8
without posting. C linked 500 against Expense 9 (original 1000, remaining 500),
with audit 167 explicitly recording journal_posted=false. Final QA counts were
31 journals / 72 lines. Original B/C journals 37/38 were unchanged.

Staging 96013 provided the approved Expense editor spacing/long-label correction.
The checkpoint additionally maps known Banking history codes to friendly labels
without altering raw audit data; this display-only addition has not been published
as a further APK. Unknown codes retain their original text.

Administrator cleanup completed on 2026-09-10 after all original row hashes
matched excluding the explicitly resolved fixture. Only synthetic batch 4,
document 3, rows 726–728, Expenses 8–10 and their related match/refund/reference/
line/journal/audit rows were deleted. All pre-QA table hashes were restored;
retained Batch 2 remains 719 rows; journal baseline is again 28 / 66. Foreign-key
checks stayed enabled and auto-increment counters were not reset.
Protected recovery record:
`/var/www/ceh-staging/private/banking-96012-qa/cleanup-recovery-20260910T222852Z.json`.

Post-cleanup checkpoint validation: all 481 Flutter tests pass, including seven
Banking action/history tests and four phone-width Expense layout tests. All
changed/new PHP files pass syntax checks; Flutter analyze reports no issues.
No QA helper, recovery data, APK,
private signing key or credential is included in the checkpoint.
