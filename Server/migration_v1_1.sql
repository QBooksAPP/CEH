CREATE TABLE IF NOT EXISTS qbook_auth_tokens (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 user_id BIGINT UNSIGNED NOT NULL,
 token_hash CHAR(64) NOT NULL,
 expires_at DATETIME NOT NULL,
 revoked_at DATETIME NULL,
 created_ip VARCHAR(45) NULL,
 user_agent VARCHAR(255) NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (id),
 UNIQUE KEY uq_auth_token_hash (token_hash),
 KEY idx_auth_user (user_id),
 KEY idx_auth_expiry (expires_at),
 CONSTRAINT fk_auth_token_user FOREIGN KEY (user_id)
 REFERENCES qbook_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
