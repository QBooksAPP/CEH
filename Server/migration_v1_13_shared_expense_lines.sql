-- NOT APPLIED TO PRODUCTION.
-- CEH Accounts Phase 2. Apply only after v1.12, a fresh backup and explicit approval.
-- Incremental only: no postings, opening balances, backfill, renumbering or deletes.

CREATE TABLE qbook_suppliers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  canonical_name VARCHAR(200) NOT NULL,
  normalized_name VARCHAR(200) NOT NULL,
  contact_person VARCHAR(200) NULL,
  phone VARCHAR(80) NULL,
  email VARCHAR(255) NULL,
  address VARCHAR(500) NULL,
  supplier_type VARCHAR(100) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NOT NULL,
  updated_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_supplier_normalized_name (normalized_name),
  KEY idx_supplier_active_name (is_active,canonical_name),
  CONSTRAINT fk_supplier_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_supplier_updated_by FOREIGN KEY (updated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_supplier_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_supplier_aliases (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  supplier_id BIGINT UNSIGNED NOT NULL,
  alias_name VARCHAR(200) NOT NULL,
  normalized_alias VARCHAR(200) NOT NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_supplier_alias_normalized (normalized_alias),
  KEY idx_supplier_alias_supplier (supplier_id),
  CONSTRAINT fk_supplier_alias_supplier FOREIGN KEY (supplier_id)
    REFERENCES qbook_suppliers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_supplier_alias_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE qbook_petty_cash_expenses
  MODIFY expense_date DATE NULL,
  MODIFY amount DECIMAL(18,2) NULL,
  MODIFY expense_account_id BIGINT UNSIGNED NULL,
  MODIFY supplier_paid_to VARCHAR(200) NULL,
  MODIFY description VARCHAR(500) NULL,
  ADD COLUMN line_model_version TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER amount,
  ADD COLUMN supplier_id BIGINT UNSIGNED NULL AFTER expense_account_id,
  ADD CONSTRAINT fk_petty_expense_supplier FOREIGN KEY (supplier_id)
    REFERENCES qbook_suppliers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT chk_petty_line_model_version CHECK (line_model_version IN (0,1));

CREATE TABLE qbook_petty_cash_expense_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  line_no INT UNSIGNED NOT NULL,
  item_description VARCHAR(500) NOT NULL,
  expense_account_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  quantity DECIMAL(18,4) NULL,
  unit_price DECIMAL(18,2) NULL,
  client_id BIGINT UNSIGNED NULL,
  project_id BIGINT UNSIGNED NULL,
  mixer_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_expense_line_no (expense_id,line_no),
  KEY idx_petty_line_account (expense_account_id),
  KEY idx_petty_line_client (client_id),
  KEY idx_petty_line_project (project_id),
  KEY idx_petty_line_mixer (mixer_id),
  CONSTRAINT fk_petty_line_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_petty_cash_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_account FOREIGN KEY (expense_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_petty_line_positive CHECK (amount > 0.00),
  CONSTRAINT chk_petty_line_quantity CHECK (quantity IS NULL OR quantity > 0.0000),
  CONSTRAINT chk_petty_line_unit_price CHECK (unit_price IS NULL OR unit_price > 0.00),
  CONSTRAINT chk_petty_line_quantity_pair CHECK
    ((quantity IS NULL AND unit_price IS NULL) OR (quantity IS NOT NULL AND unit_price IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_petty_cash_line_reclassifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  line_id BIGINT UNSIGNED NOT NULL,
  version_no INT UNSIGNED NOT NULL,
  before_snapshot JSON NOT NULL,
  after_snapshot JSON NOT NULL,
  journal_id BIGINT UNSIGNED NULL,
  reversal_journal_id BIGINT UNSIGNED NULL,
  reason VARCHAR(500) NOT NULL,
  reclassified_by BIGINT UNSIGNED NOT NULL,
  reclassified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_line_reclass_version (line_id,version_no),
  UNIQUE KEY uq_petty_line_reclass_journal (journal_id),
  UNIQUE KEY uq_petty_line_reclass_reversal (reversal_journal_id),
  KEY idx_petty_line_reclass_expense (expense_id,id),
  CONSTRAINT fk_petty_line_reclass_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_petty_cash_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_reclass_line FOREIGN KEY (line_id)
    REFERENCES qbook_petty_cash_expense_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_reclass_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_reclass_reversal FOREIGN KEY (reversal_journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_line_reclass_actor FOREIGN KEY (reclassified_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_general_expenses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  bank_account_id BIGINT UNSIGNED NULL,
  expense_date DATE NULL,
  amount DECIMAL(18,2) NULL,
  supplier_id BIGINT UNSIGNED NULL,
  supplier_name_snapshot VARCHAR(200) NULL,
  description VARCHAR(500) NULL,
  bank_reference VARCHAR(150) NULL,
  no_receipt_reason VARCHAR(500) NULL,
  status ENUM('DRAFT','SUBMITTED','CORRECTION_REQUIRED','APPROVED','CANCELLED_NOT_SPENT','VOIDED') NOT NULL DEFAULT 'DRAFT',
  journal_id BIGINT UNSIGNED NULL,
  reversal_journal_id BIGINT UNSIGNED NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  submitted_at DATETIME NULL,
  reviewed_by BIGINT UNSIGNED NULL,
  reviewed_at DATETIME NULL,
  review_reason VARCHAR(500) NULL,
  voided_by BIGINT UNSIGNED NULL,
  voided_at DATETIME NULL,
  void_reason VARCHAR(500) NULL,
  created_from_statement_row_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_general_expense_journal (journal_id),
  UNIQUE KEY uq_general_expense_reversal (reversal_journal_id),
  UNIQUE KEY uq_general_expense_statement_source (created_from_statement_row_id),
  KEY idx_general_expense_status_date (status,expense_date),
  KEY idx_general_expense_bank_reference (bank_account_id,expense_date,bank_reference,amount),
  CONSTRAINT fk_general_expense_bank FOREIGN KEY (bank_account_id)
    REFERENCES qbook_bank_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_supplier FOREIGN KEY (supplier_id)
    REFERENCES qbook_suppliers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_reversal FOREIGN KEY (reversal_journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_creator FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_reviewer FOREIGN KEY (reviewed_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_voider FOREIGN KEY (voided_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_expense_statement_source FOREIGN KEY (created_from_statement_row_id)
    REFERENCES qbook_bank_statement_rows(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_general_expense_positive CHECK (amount IS NULL OR amount > 0.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_general_expense_references (
  reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NULL,
  issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reference_no),
  UNIQUE KEY uq_general_expense_reference_expense (expense_id),
  CONSTRAINT fk_general_expense_reference_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_general_expenses(id) ON UPDATE RESTRICT ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_general_expense_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  line_no INT UNSIGNED NOT NULL,
  item_description VARCHAR(500) NOT NULL,
  expense_account_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  quantity DECIMAL(18,4) NULL,
  unit_price DECIMAL(18,2) NULL,
  client_id BIGINT UNSIGNED NULL,
  project_id BIGINT UNSIGNED NULL,
  mixer_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_general_expense_line_no (expense_id,line_no),
  KEY idx_general_line_account (expense_account_id),
  KEY idx_general_line_client (client_id),
  KEY idx_general_line_project (project_id),
  KEY idx_general_line_mixer (mixer_id),
  CONSTRAINT fk_general_line_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_general_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_account FOREIGN KEY (expense_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_general_line_positive CHECK (amount > 0.00),
  CONSTRAINT chk_general_line_quantity CHECK (quantity IS NULL OR quantity > 0.0000),
  CONSTRAINT chk_general_line_unit_price CHECK (unit_price IS NULL OR unit_price > 0.00),
  CONSTRAINT chk_general_line_quantity_pair CHECK
    ((quantity IS NULL AND unit_price IS NULL) OR (quantity IS NOT NULL AND unit_price IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_general_expense_line_reclassifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  line_id BIGINT UNSIGNED NOT NULL,
  version_no INT UNSIGNED NOT NULL,
  before_snapshot JSON NOT NULL,
  after_snapshot JSON NOT NULL,
  journal_id BIGINT UNSIGNED NULL,
  reversal_journal_id BIGINT UNSIGNED NULL,
  reason VARCHAR(500) NOT NULL,
  reclassified_by BIGINT UNSIGNED NOT NULL,
  reclassified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_general_line_reclass_version (line_id,version_no),
  UNIQUE KEY uq_general_line_reclass_journal (journal_id),
  UNIQUE KEY uq_general_line_reclass_reversal (reversal_journal_id),
  CONSTRAINT fk_general_line_reclass_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_general_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_reclass_line FOREIGN KEY (line_id)
    REFERENCES qbook_general_expense_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_reclass_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_reclass_reversal FOREIGN KEY (reversal_journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_line_reclass_actor FOREIGN KEY (reclassified_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A refund is statement evidence for an actual bank credit. It is not created
-- by Void and it does not itself post in Phase 2; this link reserves the safe
-- future workflow and permits Void only after an actual credit is identified.
CREATE TABLE qbook_general_expense_refunds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  expense_id BIGINT UNSIGNED NOT NULL,
  statement_row_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  linked_by BIGINT UNSIGNED NOT NULL,
  linked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_general_refund_statement (statement_row_id),
  KEY idx_general_refund_expense (expense_id),
  CONSTRAINT fk_general_refund_expense FOREIGN KEY (expense_id)
    REFERENCES qbook_general_expenses(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_refund_statement FOREIGN KEY (statement_row_id)
    REFERENCES qbook_bank_statement_rows(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_general_refund_actor FOREIGN KEY (linked_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_general_refund_positive CHECK (amount > 0.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
