-- NOT APPLIED TO PRODUCTION.
-- CEH Accounts Phase 1.3. Apply only after migration v1.11, a fresh backup,
-- and explicit approval.
--
-- Issued CEH-PC numbers survive hard deletion of an unposted draft. The
-- reference row becomes a permanent tombstone and its AUTO_INCREMENT value is
-- never reused or reassigned.

ALTER TABLE qbook_petty_cash_expense_references
  DROP FOREIGN KEY fk_petty_cash_expense_reference_expense;

ALTER TABLE qbook_petty_cash_expense_references
  MODIFY expense_id BIGINT UNSIGNED NULL;

ALTER TABLE qbook_petty_cash_expense_references
  ADD CONSTRAINT fk_petty_cash_expense_reference_expense
    FOREIGN KEY (expense_id)
    REFERENCES qbook_petty_cash_expenses(id)
    ON UPDATE RESTRICT
    ON DELETE SET NULL;

ALTER TABLE qbook_petty_cash_expenses
  MODIFY status ENUM(
    'DRAFT',
    'SUBMITTED',
    'CORRECTION_REQUIRED',
    'APPROVED',
    'CANCELLED_NOT_SPENT',
    'VOIDED'
  ) NOT NULL DEFAULT 'DRAFT',
  ADD COLUMN reversal_journal_id BIGINT UNSIGNED NULL AFTER journal_id,
  ADD COLUMN voided_by BIGINT UNSIGNED NULL AFTER review_reason,
  ADD COLUMN voided_at DATETIME NULL AFTER voided_by,
  ADD COLUMN void_reason VARCHAR(500) NULL AFTER voided_at,
  ADD UNIQUE KEY uq_petty_expense_reversal_journal (reversal_journal_id),
  ADD KEY idx_petty_expense_voided_by (voided_by),
  ADD CONSTRAINT fk_petty_expense_reversal_journal
    FOREIGN KEY (reversal_journal_id)
    REFERENCES qbook_financial_journals(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT,
  ADD CONSTRAINT fk_petty_expense_voided_by
    FOREIGN KEY (voided_by)
    REFERENCES qbook_users(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT;

-- Posted expense corrections are versioned separately. The original expense,
-- evidence and journal remain immutable; each correction posts a balanced
-- expense-to-expense reclassification journal and never touches Petty Cash.
CREATE TABLE qbook_petty_cash_expense_reclassifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  prior_expense_account_id BIGINT UNSIGNED NOT NULL,
  new_expense_account_id BIGINT UNSIGNED NOT NULL,
  prior_supplier_paid_to VARCHAR(200) NOT NULL,
  new_supplier_paid_to VARCHAR(200) NOT NULL,
  prior_description VARCHAR(500) NOT NULL,
  new_description VARCHAR(500) NOT NULL,
  prior_client_id BIGINT UNSIGNED NULL,
  new_client_id BIGINT UNSIGNED NULL,
  prior_project_id BIGINT UNSIGNED NULL,
  new_project_id BIGINT UNSIGNED NULL,
  prior_mixer_id BIGINT UNSIGNED NULL,
  new_mixer_id BIGINT UNSIGNED NULL,
  journal_id BIGINT UNSIGNED NULL,
  reversal_journal_id BIGINT UNSIGNED NULL,
  reason VARCHAR(500) NOT NULL,
  reclassified_by BIGINT UNSIGNED NOT NULL,
  reclassified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_expense_reclassification_journal (journal_id),
  UNIQUE KEY uq_petty_expense_reclassification_reversal (reversal_journal_id),
  KEY idx_petty_expense_reclassification_expense (expense_id,id),
  KEY idx_petty_expense_reclassification_actor (reclassified_by),
  CONSTRAINT fk_petty_expense_reclassification_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_petty_cash_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_prior_account FOREIGN KEY (prior_expense_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_new_account FOREIGN KEY (new_expense_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_prior_client FOREIGN KEY (prior_client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_new_client FOREIGN KEY (new_client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_prior_project FOREIGN KEY (prior_project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_new_project FOREIGN KEY (new_project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_prior_mixer FOREIGN KEY (prior_mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_new_mixer FOREIGN KEY (new_mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_reversal FOREIGN KEY (reversal_journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reclassification_actor FOREIGN KEY (reclassified_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
