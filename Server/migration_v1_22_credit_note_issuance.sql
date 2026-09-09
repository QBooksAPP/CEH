-- Additive migration; staging application requires separate approval.
ALTER TABLE qbook_credit_notes ADD COLUMN document_snapshot JSON NULL;
CREATE TABLE qbook_credit_note_requests (
 actor_id BIGINT UNSIGNED NOT NULL,
 request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 payload_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 credit_note_id BIGINT UNSIGNED NOT NULL, result_json JSON NOT NULL,
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(actor_id,request_key), UNIQUE KEY uq_credit_request_note(credit_note_id),
 CONSTRAINT fk_credit_request_actor FOREIGN KEY(actor_id) REFERENCES qbook_users(id) ON DELETE RESTRICT,
 CONSTRAINT fk_credit_request_note FOREIGN KEY(credit_note_id) REFERENCES qbook_credit_notes(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
