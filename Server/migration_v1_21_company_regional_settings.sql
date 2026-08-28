-- CEH company regional-settings foundation.
-- Forward-only and incremental. This does not implement full tenant isolation,
-- foreign-currency accounting, FX conversion, or historical timestamp changes.
-- Existing operational/accounting records remain implicitly company 1.

CREATE TABLE qbook_companies (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  company_code VARCHAR(30) NOT NULL,
  display_name VARCHAR(200) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL,
  updated_by BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_company_code (company_code),
  CONSTRAINT fk_company_created_by FOREIGN KEY (created_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_company_updated_by FOREIGN KEY (updated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_company_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_companies (id,company_code,display_name,is_active)
VALUES (1,'CEH','Concrete Equipment Hire Limited',1);

ALTER TABLE qbook_users
  ADD COLUMN company_id BIGINT UNSIGNED NULL AFTER id;

UPDATE qbook_users SET company_id=1 WHERE company_id IS NULL;

ALTER TABLE qbook_users
  MODIFY COLUMN company_id BIGINT UNSIGNED NOT NULL,
  ADD KEY idx_users_company (company_id),
  ADD CONSTRAINT fk_users_company FOREIGN KEY (company_id)
    REFERENCES qbook_companies(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE TABLE qbook_company_regional_settings (
  company_id BIGINT UNSIGNED NOT NULL,
  time_zone VARCHAR(64) NOT NULL,
  date_format ENUM('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') NOT NULL,
  time_format ENUM('24_HOUR','12_HOUR') NOT NULL,
  base_currency CHAR(3) NOT NULL,
  updated_by BIGINT UNSIGNED NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (company_id),
  CONSTRAINT fk_regional_company FOREIGN KEY (company_id)
    REFERENCES qbook_companies(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_regional_updated_by FOREIGN KEY (updated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_regional_currency CHECK (base_currency IN ('NGN','GBP','USD','EUR','AED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_company_regional_settings
  (company_id,time_zone,date_format,time_format,base_currency)
VALUES (1,'Africa/Lagos','DD-MM-YYYY','24_HOUR','NGN');

CREATE TABLE qbook_company_regional_settings_audit (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  company_id BIGINT UNSIGNED NOT NULL,
  changed_by BIGINT UNSIGNED NOT NULL,
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  old_time_zone VARCHAR(64) NOT NULL,
  new_time_zone VARCHAR(64) NOT NULL,
  old_date_format ENUM('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') NOT NULL,
  new_date_format ENUM('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') NOT NULL,
  old_time_format ENUM('24_HOUR','12_HOUR') NOT NULL,
  new_time_format ENUM('24_HOUR','12_HOUR') NOT NULL,
  old_base_currency CHAR(3) NOT NULL,
  new_base_currency CHAR(3) NOT NULL,
  change_reason VARCHAR(500) NULL,
  PRIMARY KEY (id),
  KEY idx_regional_audit_company (company_id,changed_at),
  KEY idx_regional_audit_actor (changed_by,changed_at),
  CONSTRAINT fk_regional_audit_company FOREIGN KEY (company_id)
    REFERENCES qbook_companies(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_regional_audit_user FOREIGN KEY (changed_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_regional_audit_old_currency CHECK (old_base_currency IN ('NGN','GBP','USD','EUR','AED')),
  CONSTRAINT chk_regional_audit_new_currency CHECK (new_base_currency IN ('NGN','GBP','USD','EUR','AED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE qbook_invoices
  ADD COLUMN currency_code_snapshot CHAR(3) NULL AFTER payment_bank_details_snapshot,
  ADD CONSTRAINT chk_invoice_currency_snapshot CHECK
    (currency_code_snapshot IS NULL OR currency_code_snapshot IN ('NGN','GBP','USD','EUR','AED'));

ALTER TABLE qbook_estimates
  ADD COLUMN currency_code_snapshot CHAR(3) NULL AFTER payment_bank_details_snapshot,
  ADD CONSTRAINT chk_estimate_currency_snapshot CHECK
    (currency_code_snapshot IS NULL OR currency_code_snapshot IN ('NGN','GBP','USD','EUR','AED'));

ALTER TABLE qbook_customer_receipts
  ADD COLUMN currency_code_snapshot CHAR(3) NULL AFTER received_into_snapshot,
  ADD CONSTRAINT chk_receipt_currency_snapshot CHECK
    (currency_code_snapshot IS NULL OR currency_code_snapshot IN ('NGN','GBP','USD','EUR','AED'));

-- Existing issued/sent/posted NULL snapshots are intentionally not backfilled.
-- Application compatibility resolves those pre-v1.21 CEH documents as NGN.
