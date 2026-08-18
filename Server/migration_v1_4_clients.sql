-- NOT APPLIED TO PRODUCTION. Review and back up before deployment.
-- Apply after migration_v1_3_production_log.sql and before deploying the
-- Build #42.1 Client master PHP endpoints.

CREATE TABLE qbook_clients (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(150) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_clients_name (name),
  KEY idx_clients_active_name (is_active, name),
  CONSTRAINT chk_clients_active CHECK (is_active IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Existing v1.3 sessions have no reliable master record to reference, so this
-- column is nullable for historical compatibility. All new sessions created
-- through production_session_create.php require an ACTIVE client_id.
ALTER TABLE qbook_production_sessions
  ADD COLUMN client_id BIGINT UNSIGNED NULL AFTER production_date,
  ADD KEY idx_production_sessions_client_date (client_id, production_date),
  ADD CONSTRAINT fk_production_session_client
    FOREIGN KEY (client_id) REFERENCES qbook_clients(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT;
