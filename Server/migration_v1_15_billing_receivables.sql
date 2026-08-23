-- CEH Accounts Phase 3: Billing & Receivables (incremental, no postings/backfill).

INSERT INTO qbook_accounts_chart(code,name,account_type,parent_id,is_postable)
VALUES
('1150','WHT Receivable','ASSET',(SELECT id FROM qbook_accounts_chart WHERE code='1000'),1),
('2310','Output VAT Payable','LIABILITY',(SELECT id FROM qbook_accounts_chart WHERE code='2300'),1),
('2400','Customer Advances / Deposits','LIABILITY',(SELECT id FROM qbook_accounts_chart WHERE code='2000'),1);

CREATE TABLE qbook_financial_account_roles (
  role_code VARCHAR(50) NOT NULL,
  account_id BIGINT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  updated_by BIGINT UNSIGNED NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY(role_code), KEY idx_account_roles_account(account_id),
  CONSTRAINT fk_account_roles_account FOREIGN KEY(account_id) REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_account_roles_user FOREIGN KEY(updated_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_account_roles_active CHECK(is_active IN(0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_financial_account_roles(role_code,account_id) VALUES
('TRADE_RECEIVABLES',(SELECT id FROM qbook_accounts_chart WHERE code='1100')),
('ZENITH_BANK',(SELECT id FROM qbook_accounts_chart WHERE code='1011')),
('OUTPUT_VAT_PAYABLE',(SELECT id FROM qbook_accounts_chart WHERE code='2310')),
('WHT_RECEIVABLE',(SELECT id FROM qbook_accounts_chart WHERE code='1150')),
('CUSTOMER_ADVANCES',(SELECT id FROM qbook_accounts_chart WHERE code='2400'));

CREATE TABLE qbook_tax_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(40) NOT NULL, name VARCHAR(150) NOT NULL,
  tax_type ENUM('VAT','WHT') NOT NULL,
  rate_percent DECIMAL(9,6) NOT NULL,
  calculation_base ENUM('NET','GROSS','MANUAL') NOT NULL DEFAULT 'NET',
  account_role_code VARCHAR(50) NOT NULL,
  effective_from DATE NOT NULL, effective_to DATE NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), UNIQUE KEY uq_tax_code_effective(code,effective_from),
  KEY idx_tax_type_effective(tax_type,is_active,effective_from,effective_to),
  CONSTRAINT fk_tax_account_role FOREIGN KEY(account_role_code) REFERENCES qbook_financial_account_roles(role_code) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_tax_created_by FOREIGN KEY(created_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_tax_rate CHECK(rate_percent >= 0 AND rate_percent <= 100),
  CONSTRAINT chk_tax_dates CHECK(effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT chk_tax_active CHECK(is_active IN(0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_invoice_settings (
  id TINYINT UNSIGNED NOT NULL,
  company_legal_name VARCHAR(200) NULL, company_address VARCHAR(500) NULL,
  tax_identifier VARCHAR(100) NULL, payment_bank_details VARCHAR(500) NULL,
  default_terms ENUM('ADVANCE_PAYMENT','DUE_ON_ISSUE','NET_DAYS','FIXED_DUE_DATE','CUSTOM') NOT NULL DEFAULT 'ADVANCE_PAYMENT',
  default_terms_text VARCHAR(500) NOT NULL DEFAULT 'Advance Payment',
  updated_by BIGINT UNSIGNED NULL, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY(id), CONSTRAINT chk_invoice_settings_singleton CHECK(id=1),
  CONSTRAINT fk_invoice_settings_user FOREIGN KEY(updated_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO qbook_invoice_settings(id) VALUES(1);

CREATE TABLE qbook_invoice_references(reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(reference_no)) ENGINE=InnoDB;
CREATE TABLE qbook_customer_receipt_references(reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(reference_no)) ENGINE=InnoDB;
CREATE TABLE qbook_credit_note_references(reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(reference_no)) ENGINE=InnoDB;

CREATE TABLE qbook_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, reference_no BIGINT UNSIGNED NOT NULL,
  client_id BIGINT UNSIGNED NOT NULL, client_name_snapshot VARCHAR(150) NOT NULL,
  invoice_date DATE NULL, payment_term ENUM('ADVANCE_PAYMENT','DUE_ON_ISSUE','NET_DAYS','FIXED_DUE_DATE','CUSTOM') NOT NULL DEFAULT 'ADVANCE_PAYMENT',
  terms_snapshot VARCHAR(500) NULL, due_date DATE NULL,
  vat_mode ENUM('NONE','VAT_EXCLUSIVE','VAT_INCLUSIVE') NOT NULL DEFAULT 'NONE', vat_tax_code_id BIGINT UNSIGNED NULL,
  vat_rate_snapshot DECIMAL(9,6) NULL, net_amount DECIMAL(18,2) NULL, vat_amount DECIMAL(18,2) NULL, total_amount DECIMAL(18,2) NULL,
  status ENUM('DRAFT','ISSUED','VOID') NOT NULL DEFAULT 'DRAFT', journal_id BIGINT UNSIGNED NULL,
  notes TEXT NULL, issued_at DATETIME NULL, issued_by BIGINT UNSIGNED NULL, voided_at DATETIME NULL, voided_by BIGINT UNSIGNED NULL, void_reason VARCHAR(500) NULL,
  created_by BIGINT UNSIGNED NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY(id), UNIQUE KEY uq_invoice_reference(reference_no), UNIQUE KEY uq_invoice_journal(journal_id),
  KEY idx_invoice_client_status(client_id,status,invoice_date), KEY idx_invoice_due(status,due_date),
  CONSTRAINT fk_invoice_reference FOREIGN KEY(reference_no) REFERENCES qbook_invoice_references(reference_no) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_client FOREIGN KEY(client_id) REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_vat_code FOREIGN KEY(vat_tax_code_id) REFERENCES qbook_tax_codes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_journal FOREIGN KEY(journal_id) REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_creator FOREIGN KEY(created_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_issuer FOREIGN KEY(issued_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_voider FOREIGN KEY(voided_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_invoice_due CHECK(due_date IS NULL OR invoice_date IS NULL OR due_date >= invoice_date),
  CONSTRAINT chk_invoice_amounts CHECK((status='DRAFT') OR (net_amount>=0 AND vat_amount>=0 AND total_amount=net_amount+vat_amount))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_invoice_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, invoice_id BIGINT UNSIGNED NOT NULL, line_no INT UNSIGNED NOT NULL,
  source_type ENUM('PRODUCTION_REPORT','SERVICE','EQUIPMENT_HIRE','MANUAL') NOT NULL,
  description VARCHAR(500) NOT NULL, quantity DECIMAL(14,4) NULL, unit_name VARCHAR(30) NULL, unit_price DECIMAL(18,2) NULL,
  entered_amount DECIMAL(18,2) NOT NULL, taxable TINYINT(1) NOT NULL DEFAULT 1,
  net_amount DECIMAL(18,2) NULL, vat_amount DECIMAL(18,2) NULL, gross_amount DECIMAL(18,2) NULL,
  revenue_account_id BIGINT UNSIGNED NOT NULL, project_id BIGINT UNSIGNED NULL, project_snapshot VARCHAR(200) NULL, mixer_id BIGINT UNSIGNED NULL, mixer_snapshot VARCHAR(200) NULL,
  PRIMARY KEY(id), UNIQUE KEY uq_invoice_line(invoice_id,line_no), KEY idx_invoice_line_account(revenue_account_id), KEY idx_invoice_line_project(project_id), KEY idx_invoice_line_mixer(mixer_id),
  CONSTRAINT fk_invoice_line_invoice FOREIGN KEY(invoice_id) REFERENCES qbook_invoices(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_line_account FOREIGN KEY(revenue_account_id) REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_line_project FOREIGN KEY(project_id) REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_line_mixer FOREIGN KEY(mixer_id) REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_invoice_line_amount CHECK(entered_amount > 0), CONSTRAINT chk_invoice_line_qty CHECK(quantity IS NULL OR quantity > 0),
  CONSTRAINT chk_invoice_line_price CHECK(unit_price IS NULL OR unit_price > 0), CONSTRAINT chk_invoice_line_pair CHECK((quantity IS NULL)=(unit_price IS NULL)),
  CONSTRAINT chk_invoice_line_taxable CHECK(taxable IN(0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_invoice_production_allocations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, invoice_line_id BIGINT UNSIGNED NOT NULL, production_session_id BIGINT UNSIGNED NOT NULL,
  production_report_no BIGINT UNSIGNED NOT NULL, report_reference_snapshot VARCHAR(30) NOT NULL,
  signed_m3_snapshot DECIMAL(10,2) NOT NULL, billed_m3 DECIMAL(10,2) NOT NULL, rate_snapshot DECIMAL(18,2) NOT NULL,
  status ENUM('DRAFT','COMMITTED','REVERSED') NOT NULL DEFAULT 'DRAFT', created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), UNIQUE KEY uq_invoice_line_production(invoice_line_id,production_session_id),
  KEY idx_production_billed(production_session_id,status),
  CONSTRAINT fk_invoice_production_line FOREIGN KEY(invoice_line_id) REFERENCES qbook_invoice_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_production_session FOREIGN KEY(production_session_id) REFERENCES qbook_production_sessions(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_production_report FOREIGN KEY(production_report_no) REFERENCES qbook_production_reports(report_no) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_production_billed_m3 CHECK(billed_m3 > 0 AND signed_m3_snapshot > 0 AND billed_m3 <= signed_m3_snapshot),
  CONSTRAINT chk_production_rate CHECK(rate_snapshot > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_customer_receipts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, reference_no BIGINT UNSIGNED NOT NULL, client_id BIGINT UNSIGNED NOT NULL, client_name_snapshot VARCHAR(150) NOT NULL,
  bank_account_id BIGINT UNSIGNED NOT NULL, receipt_date DATE NOT NULL, cash_amount DECIMAL(18,2) NOT NULL,
  bank_reference VARCHAR(150) NULL, narration VARCHAR(500) NULL,
  destination ENUM('TRADE_RECEIVABLES','CUSTOMER_ADVANCES') NOT NULL,
  status ENUM('DRAFT','POSTED','VOID') NOT NULL DEFAULT 'DRAFT', journal_id BIGINT UNSIGNED NULL, statement_row_id BIGINT UNSIGNED NULL,
  created_by BIGINT UNSIGNED NOT NULL, posted_by BIGINT UNSIGNED NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, posted_at DATETIME NULL,
  PRIMARY KEY(id), UNIQUE KEY uq_receipt_reference(reference_no), UNIQUE KEY uq_receipt_journal(journal_id), UNIQUE KEY uq_receipt_statement(statement_row_id),
  KEY idx_receipt_client_date(client_id,receipt_date),
  CONSTRAINT fk_receipt_reference FOREIGN KEY(reference_no) REFERENCES qbook_customer_receipt_references(reference_no) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_client FOREIGN KEY(client_id) REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_bank FOREIGN KEY(bank_account_id) REFERENCES qbook_bank_accounts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_journal FOREIGN KEY(journal_id) REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_statement FOREIGN KEY(statement_row_id) REFERENCES qbook_bank_statement_rows(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_creator FOREIGN KEY(created_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_poster FOREIGN KEY(posted_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_receipt_cash CHECK(cash_amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_receipt_wht (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, receipt_id BIGINT UNSIGNED NOT NULL UNIQUE, tax_code_id BIGINT UNSIGNED NOT NULL,
  rate_snapshot DECIMAL(9,6) NOT NULL, calculation_base_snapshot ENUM('NET','GROSS','MANUAL') NOT NULL,
  accepted_amount DECIMAL(18,2) NOT NULL, certificate_status ENUM('NOT_APPLICABLE','CERTIFICATE_PENDING','CERTIFICATE_RECEIVED') NOT NULL,
  certificate_received_at DATETIME NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), KEY idx_wht_certificate(certificate_status),
  CONSTRAINT fk_receipt_wht_receipt FOREIGN KEY(receipt_id) REFERENCES qbook_customer_receipts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_receipt_wht_code FOREIGN KEY(tax_code_id) REFERENCES qbook_tax_codes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_receipt_wht_amount CHECK(accepted_amount > 0),
  CONSTRAINT chk_wht_certificate_date CHECK((certificate_status='CERTIFICATE_RECEIVED')=(certificate_received_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_customer_receipt_allocations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, receipt_id BIGINT UNSIGNED NOT NULL, invoice_id BIGINT UNSIGNED NOT NULL,
  cash_amount DECIMAL(18,2) NOT NULL DEFAULT 0, wht_amount DECIMAL(18,2) NOT NULL DEFAULT 0, allocated_by BIGINT UNSIGNED NOT NULL, allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), UNIQUE KEY uq_receipt_invoice(receipt_id,invoice_id), KEY idx_allocation_invoice(invoice_id),
  CONSTRAINT fk_allocation_receipt FOREIGN KEY(receipt_id) REFERENCES qbook_customer_receipts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_allocation_invoice FOREIGN KEY(invoice_id) REFERENCES qbook_invoices(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_allocation_user FOREIGN KEY(allocated_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_allocation_positive CHECK(cash_amount >= 0 AND wht_amount >= 0 AND cash_amount+wht_amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_advance_applications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, receipt_id BIGINT UNSIGNED NOT NULL, invoice_id BIGINT UNSIGNED NOT NULL, amount DECIMAL(18,2) NOT NULL,
  journal_id BIGINT UNSIGNED NULL, applied_by BIGINT UNSIGNED NOT NULL, applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), UNIQUE KEY uq_advance_receipt_invoice(receipt_id,invoice_id), UNIQUE KEY uq_advance_application_journal(journal_id), KEY idx_advance_invoice(invoice_id),
  CONSTRAINT fk_advance_receipt FOREIGN KEY(receipt_id) REFERENCES qbook_customer_receipts(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_advance_invoice FOREIGN KEY(invoice_id) REFERENCES qbook_invoices(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_advance_journal FOREIGN KEY(journal_id) REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_advance_user FOREIGN KEY(applied_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_advance_amount CHECK(amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_credit_notes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, reference_no BIGINT UNSIGNED NOT NULL, invoice_id BIGINT UNSIGNED NOT NULL,
  credit_date DATE NOT NULL, reason VARCHAR(500) NOT NULL, net_amount DECIMAL(18,2) NOT NULL, vat_amount DECIMAL(18,2) NOT NULL, total_amount DECIMAL(18,2) NOT NULL,
  status ENUM('DRAFT','ISSUED','VOID') NOT NULL DEFAULT 'DRAFT', journal_id BIGINT UNSIGNED NULL, created_by BIGINT UNSIGNED NOT NULL, issued_by BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, issued_at DATETIME NULL,
  PRIMARY KEY(id), UNIQUE KEY uq_credit_reference(reference_no), UNIQUE KEY uq_credit_journal(journal_id), KEY idx_credit_invoice(invoice_id,status),
  CONSTRAINT fk_credit_reference FOREIGN KEY(reference_no) REFERENCES qbook_credit_note_references(reference_no) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_invoice FOREIGN KEY(invoice_id) REFERENCES qbook_invoices(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_journal FOREIGN KEY(journal_id) REFERENCES qbook_financial_journals(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_creator FOREIGN KEY(created_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_issuer FOREIGN KEY(issued_by) REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_credit_total CHECK(net_amount>=0 AND vat_amount>=0 AND total_amount>0 AND total_amount=net_amount+vat_amount)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_credit_note_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, credit_note_id BIGINT UNSIGNED NOT NULL, invoice_line_id BIGINT UNSIGNED NOT NULL,
  line_no INT UNSIGNED NOT NULL, description VARCHAR(500) NOT NULL, revenue_account_id BIGINT UNSIGNED NOT NULL,
  net_amount DECIMAL(18,2) NOT NULL, vat_amount DECIMAL(18,2) NOT NULL, gross_amount DECIMAL(18,2) NOT NULL,
  project_id BIGINT UNSIGNED NULL, mixer_id BIGINT UNSIGNED NULL,
  quantity_treatment ENUM('NO_QUANTITY_RELEASE','RELEASE_QUANTITY') NOT NULL DEFAULT 'NO_QUANTITY_RELEASE',
  released_m3 DECIMAL(10,2) NULL,
  PRIMARY KEY(id), UNIQUE KEY uq_credit_line(credit_note_id,line_no),
  KEY idx_credit_line_quantity_release(invoice_line_id,quantity_treatment),
  CONSTRAINT fk_credit_line_note FOREIGN KEY(credit_note_id) REFERENCES qbook_credit_notes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_line_invoice FOREIGN KEY(invoice_line_id) REFERENCES qbook_invoice_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_line_account FOREIGN KEY(revenue_account_id) REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_line_project FOREIGN KEY(project_id) REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_line_mixer FOREIGN KEY(mixer_id) REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_credit_line_total CHECK(net_amount>=0 AND vat_amount>=0 AND gross_amount>0 AND gross_amount=net_amount+vat_amount),
  CONSTRAINT chk_credit_line_quantity_release CHECK(
    (quantity_treatment='NO_QUANTITY_RELEASE' AND released_m3 IS NULL) OR
    (quantity_treatment='RELEASE_QUANTITY' AND released_m3 > 0)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_credit_note_allocations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, credit_note_id BIGINT UNSIGNED NOT NULL UNIQUE, invoice_id BIGINT UNSIGNED NOT NULL, amount DECIMAL(18,2) NOT NULL,
  allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id), KEY idx_credit_allocation_invoice(invoice_id),
  CONSTRAINT fk_credit_allocation_note FOREIGN KEY(credit_note_id) REFERENCES qbook_credit_notes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_credit_allocation_invoice FOREIGN KEY(invoice_id) REFERENCES qbook_invoices(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_credit_allocation_amount CHECK(amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- No statutory rate is seeded. Admin must configure effective VAT/WHT codes.
ALTER TABLE qbook_financial_evidence
  MODIFY COLUMN source_type ENUM('PETTY_CASH_FUNDING','PETTY_CASH_EXPENSE','GENERAL_EXPENSE','SUPPLIER_PURCHASE','PAYROLL','INVOICE','CUSTOMER_RECEIPT','WHT_CERTIFICATE','CREDIT_NOTE') NOT NULL;
