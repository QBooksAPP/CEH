-- Run only after documented preflight/backup. No automatic deployment.
CREATE TABLE qbook_bank_statement_documents (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 bank_account_id BIGINT UNSIGNED NOT NULL,
 original_filename VARCHAR(255) NOT NULL,
 file_type ENUM('CSV','XLSX') NOT NULL,
 byte_size BIGINT UNSIGNED NOT NULL,
 sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 document_data LONGBLOB NOT NULL,
 adapter VARCHAR(60) NOT NULL,
 preview_json JSON NOT NULL,
 uploaded_by BIGINT UNSIGNED NOT NULL,
 uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_bank_document(bank_account_id,sha256),
 FOREIGN KEY(bank_account_id) REFERENCES qbook_bank_accounts(id),
 FOREIGN KEY(uploaded_by) REFERENCES qbook_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
ALTER TABLE qbook_bank_import_batches
 ADD COLUMN document_id BIGINT UNSIGNED NULL,
 ADD UNIQUE KEY uq_bank_batch_document(document_id),
 ADD CONSTRAINT fk_bank_batch_document FOREIGN KEY(document_id) REFERENCES qbook_bank_statement_documents(id);
ALTER TABLE qbook_bank_statement_rows
 DROP INDEX uq_bank_statement_fingerprint,
 ADD KEY idx_bank_content_fingerprint(bank_account_id,row_fingerprint),
 ADD COLUMN source_sheet VARCHAR(100) NULL,
 ADD COLUMN source_row INT UNSIGNED NULL,
 ADD COLUMN occurrence_number INT UNSIGNED NULL,
 ADD COLUMN value_date DATE NULL,
 ADD COLUMN statement_balance DECIMAL(18,2) NULL,
 ADD UNIQUE KEY uq_bank_physical_row(import_batch_id,source_sheet,source_row);
