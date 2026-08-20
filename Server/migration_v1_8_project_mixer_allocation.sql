-- NOT APPLIED TO PRODUCTION. Take a fresh backup and review before applying.
-- Apply after migration_v1_7_job_context.sql and before deploying Build #49.1 PHP.

CREATE TABLE qbook_project_mixers (
  project_id BIGINT UNSIGNED NOT NULL,
  mixer_id BIGINT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  assigned_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (project_id, mixer_id),
  KEY idx_project_mixers_mixer_active (mixer_id, is_active, project_id),
  KEY idx_project_mixers_assigned_by (assigned_by),
  CONSTRAINT fk_project_mixers_project FOREIGN KEY (project_id)
    REFERENCES qbook_projects(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_project_mixers_mixer FOREIGN KEY (mixer_id)
    REFERENCES qbook_mixers(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_project_mixers_assigned_by FOREIGN KEY (assigned_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT chk_project_mixers_active CHECK (is_active IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Preserve each approved revision before Admin reopens it. JSON contains the
-- immutable calibration row, trials and calculated results as they stood at
-- approval. Existing rows are not guessed or backfilled.
CREATE TABLE qbook_calibration_revision_snapshots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  calibration_id BIGINT UNSIGNED NOT NULL,
  revision_no INT NOT NULL,
  status VARCHAR(20) NOT NULL,
  snapshot_json JSON NOT NULL,
  reason VARCHAR(500) NULL,
  captured_by BIGINT UNSIGNED NOT NULL,
  captured_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_calibration_revision_snapshot (calibration_id, revision_no),
  KEY idx_calibration_revision_captured_by (captured_by),
  CONSTRAINT fk_calibration_revision_calibration FOREIGN KEY (calibration_id)
    REFERENCES qbook_calibrations(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  CONSTRAINT fk_calibration_revision_captured_by FOREIGN KEY (captured_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
