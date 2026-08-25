-- CEH Accounts Phase 3: allocation-specific customer-payment WHT.
-- Incremental only: legacy receipt-level WHT rows remain valid and untouched.

CREATE TABLE qbook_customer_receipt_allocation_wht (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  receipt_allocation_id BIGINT UNSIGNED NOT NULL,
  tax_code_id BIGINT UNSIGNED NOT NULL,
  rate_snapshot DECIMAL(9,6) NOT NULL,
  calculation_base_snapshot ENUM('NET','GROSS','MANUAL') NOT NULL,
  calculation_base_amount DECIMAL(18,2) NOT NULL,
  accepted_amount DECIMAL(18,2) NOT NULL,
  certificate_status ENUM('CERTIFICATE_PENDING','CERTIFICATE_RECEIVED') NOT NULL,
  certificate_evidence_id BIGINT UNSIGNED NULL,
  certificate_received_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_receipt_allocation_wht (receipt_allocation_id),
  UNIQUE KEY uq_allocation_wht_evidence (certificate_evidence_id),
  KEY idx_allocation_wht_tax_code (tax_code_id),
  KEY idx_allocation_wht_certificate (certificate_status),
  CONSTRAINT fk_allocation_wht_allocation FOREIGN KEY (receipt_allocation_id)
    REFERENCES qbook_customer_receipt_allocations(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_allocation_wht_tax_code FOREIGN KEY (tax_code_id)
    REFERENCES qbook_tax_codes(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_allocation_wht_evidence FOREIGN KEY (certificate_evidence_id)
    REFERENCES qbook_financial_evidence(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_allocation_wht_base_amount CHECK (calculation_base_amount > 0),
  CONSTRAINT chk_allocation_wht_accepted_amount CHECK (accepted_amount > 0),
  CONSTRAINT chk_allocation_wht_certificate_date CHECK (
    (certificate_status='CERTIFICATE_RECEIVED')=(certificate_received_at IS NOT NULL)
  ),
  CONSTRAINT chk_allocation_wht_received_evidence CHECK (
    certificate_status<>'CERTIFICATE_RECEIVED' OR certificate_evidence_id IS NOT NULL
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
