# Historical invoice document compatibility

CEH-INV-000001 and CEH-INV-000003 in the preserved production export are
pre-existing accounting records with missing historical company/payment
snapshots. They remain authoritative accounting records. Their official PDFs
must not be reconstructed from current settings or later invoice snapshots.

The existing `INVOICE_SETTINGS_SNAPSHOT_MISSING` server guard remains unchanged.
The candidate shows "Original invoice PDF unavailable" for issued records with
these identity gaps, while preserving access to accounting details. Detection
uses record state and snapshot fields, never hard-coded invoice references.

This does not assert that an original PDF never existed. Draft invoices are not
historical-document failures and retain the normal issuance lifecycle.

Any future recovery requires separate approval and exact contemporaneous
evidence (an original client-issued PDF, dated backup, or equivalent A-grade
source), provenance and audit design. No backfill or recovery is authorized by
this policy. These exceptions alone are not candidate regressions; remaining
PDF, accounting and build-96 compatibility gates still apply.
