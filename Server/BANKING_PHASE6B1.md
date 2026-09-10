# Phase 6B.1: read-only Banking workspace

Based on checkpoint 5115cd987264f1ca02ff1f515f4f0ec322d26c95. No schema migration.

ADMIN-only GET endpoints:

- bank_accounts.php: existing balances plus masked account reference and statement date; latest statement selected by statement period end, import time, ID.
- bank_transactions.php: bank_account_id, page (1-based), page_size (default 50, maximum 100), direction ALL/DEBIT/CREDIT, inclusive date_from/date_to, positive exact absolute amount, literal narration/reference search, usage ALL/AVAILABLE/RESERVED_EXPENSE/EXPENSE/REFUND/PAYMENT/RECONCILED. Summary aggregates the complete filtered result. Ordering is transaction_date DESC, id DESC. Imported balance is displayed, never recomputed from a page.
- bank_statement_imports.php: bank-scoped paginated import history, original evidence metadata, totals and balances.
- bank_statement_source.php: bank_account_id + statement_row_id; resolves actual ownership before exposing a small immutable source view. No caller-supplied source ID.
- bank_statement_document.php: existing protected original retrieval remains unchanged.

No POST call, import, reconciliation, refund action, payment creation, expense creation or bank maintenance exists in the new workspace. Legacy mutation-capable Banking widget is not routed by Accounts Home. Shared business workflows are unchanged.

Phone UI explicitly selects a bank, resets filters/page on bank change, retains selection on return from details, ignores stale requests and loads one page at a time. Regional Settings format dates/currency. All repeated physical rows display normally without duplicate warnings. Status derives from actual claims, not value similarity.

Original viewing downloads authenticated bytes into private cache, verifies expected size and SHA-256, and launches Android ACTION_VIEW with a narrow FileProvider read grant. No ACTION_SEND, public URL, write permission, or broad storage permission. Cache path is restricted to bank-originals; the provider/bridge is staging-only. Download busy state clears before viewer handoff. An installed compatible spreadsheet viewer is required. This does not change the APK updater bridge or its security checks.

Local regression uses a disposable localhost database on port 33318, including two banks and 719 synthetic physical rows. No staging fixture mutation is required. Staging acceptance helper checks the retained original 719-row dataset through authenticated GETs, verifies fee counts (261/102/69), totals, history and protected bytes, then compares every table hash. Its temporary QA token is removed. No business records are written.

Deploy only the five PHP files via a new immutable staging release, retain rollback target, gracefully reload PHP-FPM, then run read-only validation before publishing 96010. No production deployment, migration or automatic commit is included.

Validation: 456 Flutter tests passed; Flutter analyze reports no issues; 24 disposable MySQL checks passed. Staging release `build-96-banking-96010-20260910T120521Z` was activated and gracefully reloaded. Authenticated verification paginated all 719 retained rows exactly once, checked fee counts 261/102/69, debit/credit counts 706/13, totals and import balances, and verified the original workbook hash. All database table hashes remained unchanged, with journals 28 / lines 66. Temporary verification authentication was removed. No statement rows were modified.
