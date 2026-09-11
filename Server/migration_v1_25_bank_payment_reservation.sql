-- Apply only after guarded schema/data preflight and backup. No historical posting.
ALTER TABLE qbook_customer_receipts
 MODIFY status ENUM('DRAFT','POSTED','VOID','CANCELLED') NOT NULL DEFAULT 'DRAFT',
 ADD COLUMN cancelled_by BIGINT UNSIGNED NULL,
 ADD COLUMN cancelled_at DATETIME NULL,
 ADD COLUMN cancellation_reason VARCHAR(500) NULL,
 ADD COLUMN draft_payload JSON NULL,
 ADD COLUMN draft_revision INT UNSIGNED NOT NULL DEFAULT 0,
 ADD COLUMN creation_request_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
 ADD COLUMN posting_payload_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
 ADD KEY idx_receipt_statement_history(statement_row_id),
 ADD COLUMN active_statement_row_id BIGINT UNSIGNED GENERATED ALWAYS AS
   (CASE WHEN status='CANCELLED' AND journal_id IS NULL THEN NULL ELSE statement_row_id END) STORED,
 ADD UNIQUE KEY uq_receipt_active_statement(active_statement_row_id),
 ADD UNIQUE KEY uq_receipt_creation_request(created_by,creation_request_key),
 ADD CONSTRAINT fk_receipt_canceller FOREIGN KEY(cancelled_by) REFERENCES qbook_users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
 DROP INDEX uq_receipt_statement;
