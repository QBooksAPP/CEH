-- CEH Accounts Phase 3.5: immutable Client Payment receipts and Estimates.
-- Incremental only. No financial posting, historical backfill, deletion,
-- truncation, cascade deletion, opening balance, or destructive rewrite.

ALTER TABLE qbook_customer_receipts
  ADD COLUMN company_legal_name_snapshot VARCHAR(200) NULL AFTER narration,
  ADD COLUMN company_address_snapshot VARCHAR(500) NULL AFTER company_legal_name_snapshot,
  ADD COLUMN tax_identifier_snapshot VARCHAR(100) NULL AFTER company_address_snapshot,
  ADD COLUMN payment_bank_details_snapshot VARCHAR(500) NULL AFTER tax_identifier_snapshot,
  ADD COLUMN received_into_snapshot VARCHAR(200) NULL AFTER payment_bank_details_snapshot,
  ADD COLUMN pdf_template_version VARCHAR(30) NULL AFTER received_into_snapshot;

CREATE TABLE qbook_estimate_references (
  reference_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  allocated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reference_no)
) ENGINE=InnoDB;

CREATE TABLE qbook_estimates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  reference_no BIGINT UNSIGNED NOT NULL,
  revision_of_estimate_id BIGINT UNSIGNED NULL,
  client_id BIGINT UNSIGNED NOT NULL,
  client_name_snapshot VARCHAR(150) NOT NULL,
  estimate_date DATE NULL,
  valid_until DATE NULL,
  vat_mode ENUM('NONE','VAT_EXCLUSIVE','VAT_INCLUSIVE') NOT NULL DEFAULT 'NONE',
  vat_tax_code_id BIGINT UNSIGNED NULL,
  vat_rate_snapshot DECIMAL(9,6) NULL,
  net_amount DECIMAL(18,2) NULL,
  vat_amount DECIMAL(18,2) NULL,
  total_amount DECIMAL(18,2) NULL,
  notes TEXT NULL,
  terms_snapshot VARCHAR(500) NULL,
  status ENUM('DRAFT','SENT','ACCEPTED','DECLINED','EXPIRED') NOT NULL DEFAULT 'DRAFT',
  company_legal_name_snapshot VARCHAR(200) NULL,
  company_address_snapshot VARCHAR(500) NULL,
  tax_identifier_snapshot VARCHAR(100) NULL,
  payment_bank_details_snapshot VARCHAR(500) NULL,
  pdf_template_version VARCHAR(30) NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  sent_by BIGINT UNSIGNED NULL,
  sent_at DATETIME NULL,
  accepted_by BIGINT UNSIGNED NULL,
  accepted_at DATETIME NULL,
  acceptance_note VARCHAR(500) NULL,
  declined_by BIGINT UNSIGNED NULL,
  declined_at DATETIME NULL,
  decline_reason VARCHAR(500) NULL,
  expired_by BIGINT UNSIGNED NULL,
  expired_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_estimate_reference (reference_no),
  KEY idx_estimate_client_status (client_id,status,estimate_date),
  KEY idx_estimate_revision (revision_of_estimate_id),
  CONSTRAINT fk_estimate_reference FOREIGN KEY (reference_no)
    REFERENCES qbook_estimate_references(reference_no) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_revision FOREIGN KEY (revision_of_estimate_id)
    REFERENCES qbook_estimates(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_vat_code FOREIGN KEY (vat_tax_code_id)
    REFERENCES qbook_tax_codes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_creator FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_sender FOREIGN KEY (sent_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_accepter FOREIGN KEY (accepted_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_decliner FOREIGN KEY (declined_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_expirer FOREIGN KEY (expired_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_estimate_dates CHECK (valid_until IS NULL OR estimate_date IS NULL OR valid_until>=estimate_date),
  CONSTRAINT chk_estimate_totals CHECK (status='DRAFT' OR (net_amount>=0 AND vat_amount>=0 AND total_amount=net_amount+vat_amount))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_estimate_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  estimate_id BIGINT UNSIGNED NOT NULL,
  line_no INT UNSIGNED NOT NULL,
  description VARCHAR(500) NOT NULL,
  quantity DECIMAL(14,4) NULL,
  unit_name VARCHAR(30) NULL,
  unit_price DECIMAL(18,2) NULL,
  entered_amount DECIMAL(18,2) NOT NULL,
  taxable TINYINT(1) NOT NULL DEFAULT 1,
  net_amount DECIMAL(18,2) NOT NULL,
  vat_amount DECIMAL(18,2) NOT NULL,
  gross_amount DECIMAL(18,2) NOT NULL,
  revenue_account_id BIGINT UNSIGNED NOT NULL,
  project_id BIGINT UNSIGNED NULL,
  project_snapshot VARCHAR(200) NULL,
  mixer_id BIGINT UNSIGNED NULL,
  mixer_snapshot VARCHAR(200) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_estimate_line (estimate_id,line_no),
  KEY idx_estimate_line_account (revenue_account_id),
  KEY idx_estimate_line_project (project_id),
  KEY idx_estimate_line_mixer (mixer_id),
  CONSTRAINT fk_estimate_line_header FOREIGN KEY (estimate_id)
    REFERENCES qbook_estimates(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_line_account FOREIGN KEY (revenue_account_id)
    REFERENCES qbook_accounts_chart(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_line_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_line_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_estimate_line_amount CHECK (entered_amount>0 AND net_amount>0 AND vat_amount>=0 AND gross_amount=net_amount+vat_amount),
  CONSTRAINT chk_estimate_line_qty CHECK (quantity IS NULL OR quantity>0),
  CONSTRAINT chk_estimate_line_price CHECK (unit_price IS NULL OR unit_price>0),
  CONSTRAINT chk_estimate_line_pair CHECK ((quantity IS NULL)=(unit_price IS NULL)),
  CONSTRAINT chk_estimate_line_taxable CHECK (taxable IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_estimate_acceptance_evidence (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  estimate_id BIGINT UNSIGNED NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  byte_size BIGINT UNSIGNED NOT NULL,
  sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  evidence_data LONGBLOB NOT NULL,
  uploaded_by BIGINT UNSIGNED NOT NULL,
  uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_estimate_acceptance_hash (estimate_id,sha256),
  CONSTRAINT fk_estimate_acceptance_estimate FOREIGN KEY (estimate_id)
    REFERENCES qbook_estimates(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_acceptance_uploader FOREIGN KEY (uploaded_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_estimate_acceptance_size CHECK (byte_size>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE qbook_invoices
  ADD COLUMN origin_estimate_id BIGINT UNSIGNED NULL AFTER reference_no,
  ADD KEY idx_invoice_origin_estimate (origin_estimate_id),
  ADD CONSTRAINT fk_invoice_origin_estimate FOREIGN KEY (origin_estimate_id)
    REFERENCES qbook_estimates(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE TABLE qbook_estimate_invoice_conversions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  estimate_line_id BIGINT UNSIGNED NOT NULL,
  invoice_line_id BIGINT UNSIGNED NOT NULL,
  converted_quantity DECIMAL(14,4) NULL,
  converted_entered_amount DECIMAL(18,2) NOT NULL,
  converted_net_amount DECIMAL(18,2) NOT NULL,
  status ENUM('DRAFT','COMMITTED','RELEASED') NOT NULL DEFAULT 'DRAFT',
  created_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  committed_at DATETIME NULL,
  released_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_estimate_conversion_invoice_line (invoice_line_id),
  KEY idx_estimate_conversion_line_status (estimate_line_id,status),
  CONSTRAINT fk_estimate_conversion_line FOREIGN KEY (estimate_line_id)
    REFERENCES qbook_estimate_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_conversion_invoice_line FOREIGN KEY (invoice_line_id)
    REFERENCES qbook_invoice_lines(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_estimate_conversion_creator FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_estimate_conversion_amounts CHECK (converted_entered_amount>0 AND converted_net_amount>0),
  CONSTRAINT chk_estimate_conversion_quantity CHECK (converted_quantity IS NULL OR converted_quantity>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
