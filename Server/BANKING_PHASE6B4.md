# Phase 6B.4 — statement-backed Client Payments

Local validation, staging migration/reload and read-only verification passed.
Physical-phone A–E acceptance passed on staging 96014. Final accounting and
guarded fixture cleanup were verified on 2026-09-11.
No production deployment is authorized. Retained Zenith Batch 2 must remain intact.

## Ownership and accounting

`bank_payment_active_owner_sql` is the shared payment predicate used by the
locked ownership guard and Refund Linkage eligibility. Only an unposted
CANCELLED payment releases its statement identity. v1.25 retains the original
statement foreign key and uniquely constrains the generated active identity.
All claimers lock the physical statement row first. Conflicting refund/payment
claims return an authoritative ownership error; they do not create a journal.

Posting delegates to `customer_payment_post_common.php`; the legacy direct
statement receipt endpoint fails closed. Posting validates immutable bank/date/
cash/reference, locks invoices in ID order, posts once and reconciles in the
same transaction. Exact retries return the posted result; altered retries fail.
WHT remains separate from bank cash and is validated against the payment date.
Unallocated cash follows the existing Client Credit accounting lifecycle.

Saved allocation intent is independent of the outstanding invoice list. Missing
or changed allocations remain visible and block posting. Removing them requires
explicit review of the resulting allocation/Client Credit decision. Posting
errors trigger authoritative refresh while retaining local intent.

## v1.25 staging migration gate

Run only the guarded administrator helper, never the SQL directly. It checks:

- selected database exactly `ceh_staging`;
- migration hash, absent generated column and existing old unique index;
- no existing statement-backed payments, five DRAFT and four POSTED receipts;
- Batch 2 = 719 transactions; journals/lines = 28/66;
- InnoDB tables, primary keys, deterministic original-column hashes/counts;
- protected pre-DDL schema/data recovery dump and checksums;
- original data unchanged immediately before and after DDL.

DDL is not transactional. A failure is a STOP condition, not permission to retry.
The helper refuses an existing backup directory. It changes no historical
payments, statement transactions or financial journal data.

## Guarded rollback

Disable the new actions/revert the PHP release before considering schema rollback.
Never restore a dump blindly. Preserve all history and auto-increment counters.
The old unique statement index can only be restored if there is no duplicate
non-null statement_row_id across ALL payment records, including cancelled ones.
If cancellation/reuse occurred, STOP: the old schema cannot represent that history.
Do not delete records or erase statement provenance to force rollback.
Do not drop cancellation/draft/idempotency fields containing new data. Retaining
the additive columns while reverting application code is preferable. Any schema
rollback requires a fresh backup, explicit compatibility checks and approval.

## Fresh local validation

- Complete Flutter suite: 495 passed (includes 37 focused payment tests).
- Flutter analyze: no issues.
- Disposable payment/refund lifecycle and concurrent retries/claims: 75 checks.
- Actual Expense HTTP endpoints/concurrent approval: 28 checks.
- Cross-workflow invoice/payment/WHT/credit/void concurrency: 105 checks.
- Banking workspace: 24 checks; import/reimport/ownership: 62 checks.
- Changed PHP syntax checks passed; disposable databases removed.

The physical-phone acceptance and cleanup results below supplement automated
validation. No production release was performed.

## Staging acceptance preparation

v1.25 preserved all 11 recorded original table hashes, Batch 2's 719 rows and
the 28-journal/66-line baseline. The immutable PHP release was switched and
PHP-FPM gracefully reloaded. Authenticated read verification preserved all
table hashes and verified the protected original workbook.

Protected fixture record:
`/var/www/ceh-staging/private/banking-96014-qa/fixture-record.json`.
Five synthetic invoice prerequisites add five journals/11 lines: 33/77 before
payment acceptance. Original row hashes and Batch 2 remain unchanged.
No Client Payment draft/posting or acceptance action was performed by preparation.

| Scenario | Statement | Client | Invoice(s) | Intended acceptance |
| --- | --- | --- | --- | --- |
| A | 729 | QA 96014 A (7) | CEH-INV-000013 | 1,000 cash, exact settlement |
| B | 730 | QA 96014 B (8) | CEH-INV-000014 | 400 cash, 600 outstanding |
| C | 731 | QA 96014 C (9) | CEH-INV-000015 / 000016 | 600 + 400 allocation |
| D | 732 | QA 96014 D (10) | None | 750 as Client Credit |
| E | 733 | QA 96014 E (11) | CEH-INV-000017 | 1,025 cash + 50 WHT = 1,075 |

E uses effective code `WHT_CONSTRUCTION_OTHER` (3), 5% NET on 1,000;
certificate pending. No production allocations are involved. After acceptance,
resolve only fixture-dependent rows and verify every original row against the
saved baseline before cleanup. Never reset auto-increment counters.

## Acceptance and cleanup completed

All A–E payments posted exactly one balanced journal each (45–49), with no
additional reconciliation journal. A settled 1,000; B allocated 400 leaving 600;
C allocated 600/400 across two invoices; D retained 750 as available Client
Credit. E journal `CEH-JRN-20260911105145-8AE9E639` debited Bank 1,025 and WHT
Receivable 50, credited Trade Receivables 1,075, and left zero outstanding with
certificate pending. Final pre-cleanup accounting was 38 journals / 88 lines.

Guarded cleanup removed synthetic batch 5/document 4, statements 729–733,
clients 7–11, invoices 13–17, receipts 10–14, prerequisite/payment journals
40–49, and their verified allocations, WHT, matches, references and audit rows.
Every pre-fixture table hash was restored. Batch 2 remains exactly 719 rows;
accounting returned to 28 journals / 66 lines. Foreign keys were never disabled
and auto-increment counters were not reset.

Protected recovery record:
`/var/www/ceh-staging/private/banking-96014-qa/cleanup-recovery-20260911T105817Z.json`.
The recovery artifact is intentionally outside Git and the public web root.
