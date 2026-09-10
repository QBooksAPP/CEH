-- Apply only after the Phase 6B.3 compatibility checks and backup.
-- Keep permanent source provenance, but permit reuse after genuine unposted cancellation.
ALTER TABLE qbook_general_expenses
 ADD KEY idx_general_expense_statement_history(created_from_statement_row_id),
 ADD COLUMN active_statement_row_id BIGINT UNSIGNED GENERATED ALWAYS AS
 (CASE WHEN status='CANCELLED_NOT_SPENT' AND journal_id IS NULL
 THEN NULL ELSE created_from_statement_row_id END) STORED,
 ADD UNIQUE KEY uq_general_expense_active_statement(active_statement_row_id),
 DROP INDEX uq_general_expense_statement_source;
