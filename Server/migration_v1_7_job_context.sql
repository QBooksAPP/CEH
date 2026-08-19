-- NOT APPLIED TO PRODUCTION. Take a fresh backup and review before applying.
-- Apply after migration_v1_6_production_reports.sql and before deploying v1.7 PHP.

CREATE TABLE qbook_projects (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(200) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_projects_client_name (client_id, name),
  KEY idx_projects_client_active_name (client_id, is_active, name),
  CONSTRAINT fk_projects_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_projects_active CHECK (is_active IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- No historical context is guessed. Existing rows remain readable with NULL links.
ALTER TABLE qbook_calibrations
  ADD COLUMN client_id BIGINT UNSIGNED NULL AFTER mixer_id,
  ADD COLUMN project_id BIGINT UNSIGNED NULL AFTER client_id,
  ADD COLUMN client_name_snapshot VARCHAR(150) NULL AFTER project_id,
  ADD COLUMN project_name_snapshot VARCHAR(200) NULL AFTER client_name_snapshot,
  ADD COLUMN stone_size VARCHAR(20) NULL AFTER project_name_snapshot,
  ADD KEY idx_calibrations_job_context (client_id, project_id, mixer_id, stone_size, status),
  ADD CONSTRAINT fk_calibrations_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT fk_calibrations_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT chk_calibrations_stone_size CHECK
    (stone_size IS NULL OR stone_size IN ('3/8"', '1/2"', '3/4 Down'));

ALTER TABLE qbook_mix_designs
  ADD COLUMN client_id BIGINT UNSIGNED NULL AFTER design_mode,
  ADD COLUMN project_id BIGINT UNSIGNED NULL AFTER client_id,
  ADD COLUMN stone_size VARCHAR(20) NULL AFTER project_id,
  ADD COLUMN client_validation_status VARCHAR(24) NULL AFTER stone_size,
  ADD COLUMN client_validated_by BIGINT UNSIGNED NULL AFTER client_validation_status,
  ADD COLUMN client_validated_at DATETIME NULL AFTER client_validated_by,
  ADD KEY idx_mix_designs_job_context (client_id, project_id, stone_size, is_active),
  ADD KEY idx_mix_designs_validated_by (client_validated_by),
  ADD CONSTRAINT fk_mix_designs_client FOREIGN KEY (client_id)
    REFERENCES qbook_clients(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT fk_mix_designs_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT fk_mix_designs_validated_by FOREIGN KEY (client_validated_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT chk_mix_designs_stone_size CHECK
    (stone_size IS NULL OR stone_size IN ('3/8"', '1/2"', '3/4 Down')),
  ADD CONSTRAINT chk_mix_designs_client_validation CHECK
    (client_validation_status IS NULL OR client_validation_status IN
      ('PENDING_VALIDATION', 'VALIDATED', 'REQUIRES_REVISION'));

-- project_site remains the immutable project-name snapshot used by existing reports.
ALTER TABLE qbook_production_sessions
  ADD COLUMN project_id BIGINT UNSIGNED NULL AFTER client_id,
  ADD KEY idx_production_sessions_project_date (project_id, production_date),
  ADD CONSTRAINT fk_production_sessions_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
