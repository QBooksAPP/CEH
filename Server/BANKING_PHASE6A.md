# Banking Phase 6A — staging import verified

Baseline: `23e2050d3cfdeb74f4f71a625a2ffdab4f14120c`.
Phase 6A is deployed to STAGING only. No Flutter Banking UI, new receipt workflow, bank maintenance or APK is included. Production is unchanged.

## Identity and overlap policy

* File identity is `(bank_account_id, SHA-256 of original server-read bytes)`. Changing the upload filename does not create another import.
* Each imported physical row has `(import_batch_id, source_sheet, source_row)` uniqueness. Original row numbers are retained, not renumbered after filtering metadata.
* A content fingerprint uses booking date, signed minor-unit amount, normalized reference and narration. Its occurrence ordinal is recorded within the file. **Content fingerprints are not unique database keys.** Identical physical rows survive separately.
* The observed Zenith Transaction Ref values repeat; they are not proven globally unique bank transaction IDs. They are retained as references, not used to discard rows. Future adapters may use a bank-guaranteed ID only after its uniqueness semantics are established.
* Exact confirmed file retries return the existing batch. Concurrent confirmations serialize on the bank account, re-read current state under locks, and create one batch/audit event.
* A different file containing an existing content fingerprint is **ambiguous overlap**, not an authoritative duplicate. Its row receives `INVALID / AMBIGUOUS_OVERLAPPING_STATEMENT`, the original file is retained, and confirmation is blocked atomically. No row is silently skipped. There is no force-import or ignore control in 6A. Overlap resolution needs a separately approved workflow. Changed descriptions/references cannot be assumed to identify the same transaction across files.
* Legacy batch hashes cannot prove source positions. A matching legacy batch is blocked for review, not relabelled as verified imported source rows.

## Protected original evidence / schema

`qbook_bank_statement_documents` stores original bytes in a protected MySQL BLOB, following CEH's authenticated document/BLOB model; never a public upload directory. It stores bank, filename, type, byte length, SHA-256, adapter, normalized preview JSON, uploader and timestamp. No update/delete route exists.

`qbook_bank_import_batches.document_id` links one document to one committed batch. Existing batch identity remains unique by bank/file hash.

`qbook_bank_statement_rows` gains source sheet/row, occurrence, value date and statement balance. The old bank/content uniqueness is replaced by a non-unique lookup index plus physical-row uniqueness. Existing rows retain all original values and nullable provenance; no synthetic provenance is invented. Original financial rows and journals are not rewritten.

Admin-only `bank_statement_document.php?document_id=...` verifies the stored hash and serves the original file as an attachment with no-store/nosniff. Normal protected database backups must include this new BLOB table and its growing storage volume.

## Zenith adapter and mapping

Adapter: `ZENITH_ACTIVITY_V1`. XLSX uses pinned MIT SimpleXLSX 1.1.18; CSV uses a real CSV parser. Unsupported adapter/type fails closed. A future bank gets an explicit adapter rather than inference from account name or guessed columns.

| Source column | Authoritative normalized field |
| --- | --- |
| A Create Date | transaction/booking date |
| B Effective Date | optional value date |
| C Description/Payee/Memo | narration |
| D Debit Amount | outgoing debit |
| E Credit Amount | incoming credit |
| D/E | signed amount = credit minus debit |
| F Balance | statement balance |
| G Transaction Ref | bank reference, not assumed unique |
| worksheet physical row | source row number |

The supplied `Activity_Statement` workbook parses **719 rows: 706 debits, 13 credits, 126 repeated-value rows, zero invalid rows**. The secondary scratch sheet is explicitly reported as excluded, not treated as transactions. Blank/footer/control rows are listed as metadata, not silently dropped transactions.

Booking date then source-row order reconciles balances; physical workbook order contains out-of-order booking dates. Import retains physical positions. Opening balance is labelled inferred from first booking balance less its movement; it is not claimed as an independently supplied bank opening balance. Closing/footer totals are checked where declared. Nigerian comma-grouped NGN amounts use integer minor units; negative sides, two positive sides, both zero, malformed money, invalid dates and broken running balances block confirmation.

Safety limits: 10 MB uploaded file; 12,000 source rows; 20 columns; 200 ZIP entries; 8 MB per expanded member / 20 MB total. External links, embedded active content, entities and oversized cell references are rejected before the XLSX parser. Formulas in the statement sheet are rejected, not evaluated. The parser does not calculate workbook formulas. Review PHP ZIP/XML/mbstring availability and memory/upload limits before deployment.

## API / preview contract

1. `POST bank_statement_upload.php`: multipart `statement`, `bank_account_id`, `adapter`; authenticated ADMIN only. Reads and hashes original bytes; saves protected document and upload audit. Creates no statement transactions or journals.
2. `GET bank_statement_preview.php?document_id=...&page=1`: 100 normalized rows per page; summary covers the whole statement, plus bank/account identity, filename, dates, debit/credit counts and values, repeated-value count, already-imported count, invalid count/reasons, opening/closing balance and excluded metadata/sheets.
3. `POST bank_statement_import.php`: `document_id`, `confirmation_sha256` from preview. Rejects caller-normalized rows as a replacement for evidence. Replans under lock and rejects stale confirmation. One transaction commits all valid rows and one import audit, with no journal.
4. Commit returns `IMPORTED`; subsequent preview of that committed document reports each source row `ALREADY IMPORTED`. Before commit a valid row is `VALID`; invalid rows include an explicit reason. No partial import/ignored-row action exists.

The former JSON-only import contract is deliberately retired. Existing disabled mobile import UI stays disabled. Existing non-binding +/-3-day expense/funding match suggestions remain; repeated rows are no longer labelled possible duplicates merely by equality. Suggestions do not consume rows or post journals.

## Shared ownership rules

Every existing consumer locks the physical statement row in a transaction and reads current ownership under locking reads. A refund, existing match/reconciled state, another active statement-derived expense or posted statement-derived receipt blocks incompatible use. The owning expense/receipt is allowed only for its own lifecycle; database unique constraints remain in force. Existing source/date/bank/direction/amount/permission checks remain.

Guard call sites: reconciliation, expense creation/update/approval, refund linkage, and the already-existing receipt-from-statement endpoint. The last is safety hardening only, not implementation of a new receipt UI/workflow. Statement-derived expense date/reference/amount cannot drift away from its immutable statement before approval. Refund linking still posts no journal.

The missing normalization dependency is now a shared parser dependency explicitly required by reconciliation. A runtime bootstrap regression loads the actual endpoint declarations and calls the helper without invoking the endpoint mutation.

InnoDB deadlocks/lock timeouts roll the whole operation back; they must never be treated as success. Caller retries import using the same document ID. No unlink/delete/correction lifecycle is introduced.

## Staging migration procedure

1. Maintenance gate: stop staging bank writes and back up schema plus all affected tables/evidence using the existing protected backup procedure.
2. Run `bank_import_migration_preflight.sql` selecting exactly `ceh_staging`; require InnoDB, old expected indexes, no new document table, no conflicting ownership, and record full table hashes/counts. Also inspect all existing legacy claims, not only row status. Stop on discrepancies.
3. Verify PHP-FPM has ZIP, SimpleXML/libxml, zlib and mbstring; check upload/post/memory limits and MySQL `max_allowed_packet` against the 10 MB file plus preview payload (at least 32 MB packet headroom). Do not change configuration without approval.
4. Apply `migration_v1_23_bank_import_foundation.sql` once during maintenance. MySQL DDL is not an all-or-nothing transaction: inspect and recover on any error, never blindly rerun.
5. Compare original-column hashes for every legacy row, bank batch and journal; only additive nullable columns/indexes and an empty document table may differ.
6. Deploy a reviewed immutable release only after separate approval. Atomically switch, gracefully reload `php8.3-fpm`, then verify health, ADMIN authorization, document access protection and a controlled synthetic import. No current code runs these steps automatically.

## Rollback

`rollback_v1_23_bank_import_foundation.php` is CLI/root-only, explicitly bound to localhost `ceh_staging` and requires the maintenance flag. It refuses schema rollback if any new document or provenance row exists, or if restoring the old content-unique index would lose valid repeated rows. Empty-feature rollback removes only empty new structures/columns and restores the old index. It does not reset counters.

If new evidence/imports exist, preserve them. Keep the schema and disable bank import/consumer writes during application rollback until a compatible release is restored. Do not restore the old duplicate-discarding writer against the new data. Never delete original evidence or legitimate repeated rows merely to make rollback fit. Use the protected backup and a separately reviewed recovery plan if DDL partially failed.

## Validation

Pre-deployment validation: 449 Flutter tests pass; Flutter analyze reports **No issues found**. 41 parser/pure checks; 30 disposable-MySQL import/ownership/migration checks (including concurrent confirmations/claims); 12 reconciliation dependency checks; 28 existing refund checks; 1,725 existing Credit Note rounding checks; billing VAT math regression passes. All 20 changed/new PHP files lint successfully.

Disposable MySQL tests use port 33318 and a fixed throwaway database, refuse a pre-existing database, and drop only their own database afterward. No real statement bytes, staging/production data, credentials or artifacts are in these tests or committed to Git.

## Controlled staging acceptance

Post-import checkpoint validation: complete Flutter suite **449 passed**, Flutter analyze **No issues found**; parser checks **41**, reconciliation dependency checks **12**, and all **20** changed/new PHP files lint cleanly. No Flutter/Android/updater or CI configuration changes are included.

The v1.23 migration preserved all ten recorded data hashes. The immutable PHP release was activated and PHP-FPM gracefully reloaded; health and authentication boundaries passed. Protected original document 1 was previewed and retried before separately authorized confirmation.

The authenticated application import committed exactly 719 physical rows into one batch (ID 2). All source provenance/data matched the approved preview. Counts: 706 debits / 13 credits; debit total NGN 41,851,345.01; credit total NGN 33,205,837.50. Opening NGN 17,324,986.95 plus credits minus debits equals closing NGN 8,679,479.44 exactly.

All repeated legitimate fee rows remain: NGN 50 = 258 debits + 3 credits; NGN 53.75 = 100 debits + 2 credits; NGN 26.88 = 69 debits. All 719 rows are UNMATCHED. A single confirmation retry returned the same batch with replayed=true; every table hash remained unchanged across retry, and preview then reported 719 already-imported source rows.

Journals remain 28 / 66 lines. All other table hashes and existing audit rows remained unchanged; one BANK_STATEMENT_IMPORTED event was added. Temporary QA authentication was removed. The imported rows are intentionally retained for Phase 6B. Protected verification records are at `/var/www/ceh-staging/private/banking-phase6a-import`; migration recovery records are at `/var/www/ceh-staging/private/migration-backups/banking-phase6a`.

Schema rollback is now deliberately blocked by retained evidence/import data. Never delete these rows to satisfy the empty-feature rollback guard.

## Exact repository change inventory

Paths below are relative to `C:\Users\ali\CEH APP Project\Source\CEH`.

Modified:

* `Server/bank_reconcile.php`
* `Server/bank_statement_import.php`
* `Server/customer_receipt_from_statement.php`
* `Server/general_expense_create.php`
* `Server/general_expense_refunds_common.php`
* `Server/general_expense_review.php`
* `Server/general_expense_update.php`
* `test/accounts_phase1_test.dart`
* `test/accounts_phase2_test.dart`
* `test/refund_linkage_mysql_test.php`

Added:

* `Server/BANKING_PHASE6A.md`
* `Server/bank_import_common.php`
* `Server/bank_import_migration_preflight.sql`
* `Server/bank_row_usage.php`
* `Server/bank_statement_document.php`
* `Server/bank_statement_parser.php`
* `Server/bank_statement_preview.php`
* `Server/bank_statement_upload.php`
* `Server/migration_v1_23_bank_import_foundation.sql`
* `Server/rollback_v1_23_bank_import_foundation.php`
* `Server/vendor/simplexlsx/CEH-PIN.md`
* `Server/vendor/simplexlsx/LICENSE.md`
* `Server/vendor/simplexlsx/SimpleXLSX.php`
* `Server/vendor/simplexlsx/SimpleXLSXEx.php`
* `test/accounts_bank_import_foundation_test.dart`
* `test/bank_import_mysql_test.php`
* `test/bank_import_pure_test.php`
* `test/bank_reconcile_dependencies_test.php`

Validation logs and operational helpers are outside the repository in `C:\Users\ali\Documents\CEH Codex`. No real statement workbook, signing material, secrets or publication artifacts are included in this checkpoint.
