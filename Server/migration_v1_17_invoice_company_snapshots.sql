-- CEH Accounts: immutable customer-facing company snapshots for issued invoices.
-- Incremental only: existing issued invoices deliberately remain NULL.
-- Historical values must be established through a separately reviewed,
-- evidence-backed remediation; current settings are never assumed to be historical.

ALTER TABLE qbook_invoices
  ADD COLUMN company_legal_name_snapshot VARCHAR(200) NULL AFTER terms_snapshot,
  ADD COLUMN company_address_snapshot VARCHAR(500) NULL AFTER company_legal_name_snapshot,
  ADD COLUMN tax_identifier_snapshot VARCHAR(100) NULL AFTER company_address_snapshot,
  ADD COLUMN payment_bank_details_snapshot VARCHAR(500) NULL AFTER tax_identifier_snapshot;
