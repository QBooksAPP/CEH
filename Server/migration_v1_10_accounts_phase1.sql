-- NOT APPLIED TO PRODUCTION.
-- CEH Accounts Phase 1. Apply only after migrations v1.1 through v1.9,
-- a fresh production backup, and explicit approval.
-- All foreign keys are restrictive: financial evidence must not be cascaded.

CREATE TABLE qbook_accounts_chart (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(20) NOT NULL,
  name VARCHAR(150) NOT NULL,
  account_type ENUM('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE') NOT NULL,
  parent_id BIGINT UNSIGNED NULL,
  is_postable TINYINT(1) NOT NULL DEFAULT 1,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_accounts_chart_code (code),
  KEY idx_accounts_chart_parent (parent_id),
  CONSTRAINT fk_accounts_chart_parent FOREIGN KEY (parent_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_accounts_chart (code,name,account_type,parent_id,is_postable) VALUES
('1000','Assets','ASSET',NULL,0),
('2000','Liabilities','LIABILITY',NULL,0),
('3000','Equity','EQUITY',NULL,0),
('4000','Revenue','INCOME',NULL,0),
('5000','Direct Costs','EXPENSE',NULL,0),
('6000','Operating Expenses','EXPENSE',NULL,0),
('7000','Payroll Costs','EXPENSE',NULL,0);

INSERT INTO qbook_accounts_chart (code,name,account_type,parent_id,is_postable) VALUES
('1010','Bank Accounts','ASSET',(SELECT id FROM qbook_accounts_chart p WHERE p.code='1000'),0),
('1100','Trade Receivables','ASSET',(SELECT id FROM qbook_accounts_chart p WHERE p.code='1000'),1),
('1200','Petty Cash Control','ASSET',(SELECT id FROM qbook_accounts_chart p WHERE p.code='1000'),1),
('1300','Staff Advances','ASSET',(SELECT id FROM qbook_accounts_chart p WHERE p.code='1000'),1),
('1400','Prepayments','ASSET',(SELECT id FROM qbook_accounts_chart p WHERE p.code='1000'),1),
('2100','Trade Payables','LIABILITY',(SELECT id FROM qbook_accounts_chart p WHERE p.code='2000'),1),
('2200','Payroll Liabilities','LIABILITY',(SELECT id FROM qbook_accounts_chart p WHERE p.code='2000'),1),
('2300','Tax Liabilities','LIABILITY',(SELECT id FROM qbook_accounts_chart p WHERE p.code='2000'),1),
('4100','Concrete Production Revenue','INCOME',(SELECT id FROM qbook_accounts_chart p WHERE p.code='4000'),1),
('4200','Equipment Hire Revenue','INCOME',(SELECT id FROM qbook_accounts_chart p WHERE p.code='4000'),1),
('4300','Pumping and Transport Revenue','INCOME',(SELECT id FROM qbook_accounts_chart p WHERE p.code='4000'),1),
('5010','Diesel Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='5000'),1),
('5020','Materials Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='5000'),1),
('5030','Site Labour','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='5000'),1),
('5040','Transport Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='5000'),1),
('6010','Repairs and Parts','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='6000'),1),
('6020','Administration Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='6000'),1),
('6030','Utilities Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='6000'),1),
('6090','Other Operating Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='6000'),1),
('7010','Salary and Wage Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='7000'),1),
('7020','Site Allowance Expense','EXPENSE',(SELECT id FROM qbook_accounts_chart p WHERE p.code='7000'),1);

INSERT INTO qbook_accounts_chart (code,name,account_type,parent_id,is_postable)
VALUES ('1011','Zenith Bank','ASSET',
  (SELECT id FROM qbook_accounts_chart p WHERE p.code='1010'),1);

CREATE TABLE qbook_bank_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(150) NOT NULL,
  bank_name VARCHAR(150) NOT NULL,
  account_reference VARCHAR(100) NULL,
  currency CHAR(3) NOT NULL DEFAULT 'NGN',
  ledger_account_id BIGINT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bank_accounts_ledger (ledger_account_id),
  KEY idx_bank_accounts_created_by (created_by),
  CONSTRAINT fk_bank_accounts_ledger FOREIGN KEY (ledger_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bank_accounts_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_bank_accounts (name,bank_name,currency,ledger_account_id)
SELECT 'Zenith Bank','Zenith Bank','NGN',id
FROM qbook_accounts_chart WHERE code='1011';

CREATE TABLE qbook_petty_cash_custodians (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  designated_by BIGINT UNSIGNED NOT NULL,
  designated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by BIGINT UNSIGNED NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_custodian_user (user_id),
  KEY idx_petty_custodian_designated_by (designated_by),
  KEY idx_petty_custodian_updated_by (updated_by),
  CONSTRAINT fk_petty_custodian_user FOREIGN KEY (user_id)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_custodian_designated_by FOREIGN KEY (designated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_custodian_updated_by FOREIGN KEY (updated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_financial_journals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  reference_no VARCHAR(40) NOT NULL,
  transaction_date DATE NOT NULL,
  description VARCHAR(500) NOT NULL,
  source_module VARCHAR(60) NOT NULL,
  source_record_id BIGINT UNSIGNED NOT NULL,
  entry_kind ENUM('ORIGINAL','REVERSAL','REPLACEMENT') NOT NULL DEFAULT 'ORIGINAL',
  status ENUM('POSTED','REVERSED') NOT NULL DEFAULT 'POSTED',
  reversal_of_id BIGINT UNSIGNED NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  approved_by BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  posted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reversed_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_financial_journal_reference (reference_no),
  UNIQUE KEY uq_financial_journal_source
    (source_module,source_record_id,entry_kind),
  UNIQUE KEY uq_financial_journal_reversal (reversal_of_id),
  KEY idx_financial_journal_created_by (created_by),
  KEY idx_financial_journal_approved_by (approved_by),
  CONSTRAINT fk_financial_journal_reversal FOREIGN KEY (reversal_of_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_journal_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_journal_approved_by FOREIGN KEY (approved_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_financial_journal_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  journal_id BIGINT UNSIGNED NOT NULL,
  line_no INT UNSIGNED NOT NULL,
  account_id BIGINT UNSIGNED NOT NULL,
  description VARCHAR(500) NULL,
  debit DECIMAL(18,2) NOT NULL DEFAULT 0.00,
  credit DECIMAL(18,2) NOT NULL DEFAULT 0.00,
  client_id BIGINT UNSIGNED NULL,
  project_id BIGINT UNSIGNED NULL,
  mixer_id BIGINT UNSIGNED NULL,
  custodian_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_financial_journal_line (journal_id,line_no),
  KEY idx_financial_line_account (account_id),
  KEY idx_financial_line_client (client_id),
  KEY idx_financial_line_project (project_id),
  KEY idx_financial_line_mixer (mixer_id),
  KEY idx_financial_line_custodian (custodian_user_id),
  CONSTRAINT chk_financial_line_one_side CHECK
    ((debit > 0.00 AND credit = 0.00) OR (credit > 0.00 AND debit = 0.00)),
  CONSTRAINT fk_financial_line_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_line_account FOREIGN KEY (account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_line_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_line_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_line_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_financial_line_custodian FOREIGN KEY (custodian_user_id)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_petty_cash_fundings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  bank_account_id BIGINT UNSIGNED NOT NULL,
  custodian_user_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  funding_date DATE NOT NULL,
  bank_reference VARCHAR(150) NOT NULL,
  description VARCHAR(500) NULL,
  journal_id BIGINT UNSIGNED NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_funding_journal (journal_id),
  UNIQUE KEY uq_petty_funding_bank_reference
    (bank_account_id,funding_date,bank_reference,amount),
  KEY idx_petty_funding_bank_date (bank_account_id,funding_date),
  KEY idx_petty_funding_custodian (custodian_user_id,funding_date),
  KEY idx_petty_funding_created_by (created_by),
  CONSTRAINT chk_petty_funding_positive CHECK (amount > 0.00),
  CONSTRAINT fk_petty_funding_bank FOREIGN KEY (bank_account_id)
    REFERENCES qbook_bank_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_funding_custodian FOREIGN KEY (custodian_user_id)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_funding_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_funding_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_petty_cash_expenses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  custodian_user_id BIGINT UNSIGNED NOT NULL,
  expense_date DATE NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  expense_account_id BIGINT UNSIGNED NOT NULL,
  supplier_paid_to VARCHAR(200) NOT NULL,
  description VARCHAR(500) NOT NULL,
  client_id BIGINT UNSIGNED NULL,
  project_id BIGINT UNSIGNED NULL,
  mixer_id BIGINT UNSIGNED NULL,
  status ENUM('DRAFT','SUBMITTED','CORRECTION_REQUIRED','APPROVED','CANCELLED_NOT_SPENT') NOT NULL DEFAULT 'DRAFT',
  no_receipt_reason VARCHAR(500) NULL,
  journal_id BIGINT UNSIGNED NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  submitted_at DATETIME NULL,
  reviewed_by BIGINT UNSIGNED NULL,
  reviewed_at DATETIME NULL,
  review_reason VARCHAR(500) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_petty_expense_journal (journal_id),
  KEY idx_petty_expense_custodian_status (custodian_user_id,status,expense_date),
  KEY idx_petty_expense_account (expense_account_id),
  KEY idx_petty_expense_client (client_id),
  KEY idx_petty_expense_project (project_id),
  KEY idx_petty_expense_mixer (mixer_id),
  KEY idx_petty_expense_created_by (created_by),
  KEY idx_petty_expense_reviewed_by (reviewed_by),
  CONSTRAINT chk_petty_expense_positive CHECK (amount > 0.00),
  CONSTRAINT fk_petty_expense_custodian FOREIGN KEY (custodian_user_id)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_account FOREIGN KEY (expense_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_journal FOREIGN KEY (journal_id)
    REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_petty_expense_reviewed_by FOREIGN KEY (reviewed_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_financial_evidence (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  source_type ENUM('PETTY_CASH_FUNDING','PETTY_CASH_EXPENSE','GENERAL_EXPENSE','SUPPLIER_PURCHASE','PAYROLL') NOT NULL,
  source_record_id BIGINT UNSIGNED NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  byte_size BIGINT UNSIGNED NOT NULL,
  sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  storage_driver ENUM('MYSQL_BLOB','PRIVATE_FILE','OBJECT_STORAGE') NOT NULL DEFAULT 'MYSQL_BLOB',
  storage_key VARCHAR(500) NULL,
  evidence_data LONGBLOB NULL,
  uploaded_by BIGINT UNSIGNED NOT NULL,
  uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_financial_evidence_source_hash (source_type,source_record_id,sha256),
  KEY idx_financial_evidence_uploader (uploaded_by),
  CONSTRAINT fk_financial_evidence_uploader FOREIGN KEY (uploaded_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_bank_import_batches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  bank_account_id BIGINT UNSIGNED NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  file_type ENUM('CSV','XLSX') NOT NULL,
  file_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  statement_from DATE NULL,
  statement_to DATE NULL,
  opening_balance DECIMAL(18,2) NULL,
  closing_balance DECIMAL(18,2) NULL,
  imported_by BIGINT UNSIGNED NOT NULL,
  imported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bank_import_file (bank_account_id,file_sha256),
  KEY idx_bank_import_imported_by (imported_by),
  CONSTRAINT fk_bank_import_bank FOREIGN KEY (bank_account_id)
    REFERENCES qbook_bank_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bank_import_imported_by FOREIGN KEY (imported_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_bank_statement_rows (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  import_batch_id BIGINT UNSIGNED NOT NULL,
  bank_account_id BIGINT UNSIGNED NOT NULL,
  transaction_date DATE NOT NULL,
  amount DECIMAL(18,2) NOT NULL,
  bank_reference VARCHAR(150) NULL,
  narration VARCHAR(500) NOT NULL,
  row_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  status ENUM('UNMATCHED','POTENTIAL_MATCH','POSSIBLE_DUPLICATE','MATCHED','RECONCILED') NOT NULL DEFAULT 'UNMATCHED',
  potential_source_type VARCHAR(60) NULL,
  potential_source_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bank_statement_fingerprint (bank_account_id,row_fingerprint),
  KEY idx_bank_statement_batch (import_batch_id),
  KEY idx_bank_statement_match_state (bank_account_id,status,transaction_date),
  CONSTRAINT chk_bank_statement_nonzero CHECK (amount <> 0.00),
  CONSTRAINT fk_bank_statement_batch FOREIGN KEY (import_batch_id)
    REFERENCES qbook_bank_import_batches(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bank_statement_bank FOREIGN KEY (bank_account_id)
    REFERENCES qbook_bank_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_bank_matches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  statement_row_id BIGINT UNSIGNED NOT NULL,
  source_type VARCHAR(60) NOT NULL,
  source_record_id BIGINT UNSIGNED NOT NULL,
  match_method ENUM('ADMIN_CONFIRMED','EXACT_REFERENCE') NOT NULL DEFAULT 'ADMIN_CONFIRMED',
  matched_by BIGINT UNSIGNED NOT NULL,
  matched_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bank_match_statement_row (statement_row_id),
  UNIQUE KEY uq_bank_match_source (source_type,source_record_id),
  KEY idx_bank_match_user (matched_by),
  CONSTRAINT fk_bank_match_row FOREIGN KEY (statement_row_id)
    REFERENCES qbook_bank_statement_rows(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_bank_match_user FOREIGN KEY (matched_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_financial_audit (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_type VARCHAR(80) NOT NULL,
  source_type VARCHAR(60) NOT NULL,
  source_record_id BIGINT UNSIGNED NOT NULL,
  actor_user_id BIGINT UNSIGNED NOT NULL,
  details_json JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_financial_audit_source (source_type,source_record_id,created_at),
  KEY idx_financial_audit_actor (actor_user_id,created_at),
  CONSTRAINT fk_financial_audit_actor FOREIGN KEY (actor_user_id)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
