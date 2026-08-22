-- NOT APPLIED TO PRODUCTION.
-- CEH Accounts Phase 1.1. Apply only after migration v1.10, a fresh backup,
-- and explicit approval.
--
-- This independent AUTO_INCREMENT sequence is intentionally separate from the
-- petty-cash expense row id. InnoDB serializes allocation and may leave gaps
-- after rollback, but an issued number is never reused. Existing expenses are
-- deliberately not backfilled or silently renumbered by this migration.
-- Pre-v1.11 test records remain "Reference pending" until a separately
-- reviewed go-live cleanup after a fresh backup. Any pre-live sequence reset
-- belongs only to that approved cleanup. Once live Accounts operation begins,
-- CEH-PC references must never be reset, reused, renumbered, or reassigned.

CREATE TABLE qbook_petty_cash_expense_references (
  reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reference_no),
  UNIQUE KEY uq_petty_cash_expense_reference_expense (expense_id),
  CONSTRAINT fk_petty_cash_expense_reference_expense
    FOREIGN KEY (expense_id)
    REFERENCES qbook_petty_cash_expenses(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
