-- NOT APPLIED TO PRODUCTION. Back up and review before deployment.
-- Apply after migration_v1_2_settings_calibration_revision.sql.

CREATE TABLE qbook_production_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_date DATE NOT NULL,
  client_name VARCHAR(150) NOT NULL,
  project_site VARCHAR(200) NOT NULL,
  mixer_id BIGINT UNSIGNED NOT NULL,
  mixer_code_snapshot VARCHAR(50) NOT NULL,
  mixer_name_snapshot VARCHAR(150) NOT NULL,
  loading_point VARCHAR(200) NOT NULL,
  discharge_point VARCHAR(200) NOT NULL,
  operator_id BIGINT UNSIGNED NOT NULL,
  operator_name_snapshot VARCHAR(150) NOT NULL,
  notes TEXT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  signed_at DATETIME NULL,
  PRIMARY KEY (id),
  KEY idx_production_sessions_operator_date (operator_id, production_date),
  KEY idx_production_sessions_status_date (status, production_date),
  KEY idx_production_sessions_mixer_date (mixer_id, production_date),
  CONSTRAINT fk_production_session_mixer FOREIGN KEY (mixer_id) REFERENCES qbook_mixers(id),
  CONSTRAINT fk_production_session_operator FOREIGN KEY (operator_id) REFERENCES qbook_users(id),
  CONSTRAINT chk_production_session_status CHECK (status IN ('OPEN', 'SIGNED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_production_loads (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_session_id BIGINT UNSIGNED NOT NULL,
  load_number INT UNSIGNED NOT NULL,
  volume_m3 DECIMAL(8,2) NOT NULL,
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  recorded_by BIGINT UNSIGNED NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_production_load_number (production_session_id, load_number),
  KEY idx_production_load_recorded_by (recorded_by),
  KEY idx_production_load_updated_by (updated_by),
  CONSTRAINT fk_production_load_session FOREIGN KEY (production_session_id)
    REFERENCES qbook_production_sessions(id),
  CONSTRAINT fk_production_load_recorded_by FOREIGN KEY (recorded_by) REFERENCES qbook_users(id),
  CONSTRAINT fk_production_load_updated_by FOREIGN KEY (updated_by) REFERENCES qbook_users(id),
  CONSTRAINT chk_production_load_volume CHECK (volume_m3 > 0 AND volume_m3 <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_production_load_revisions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_load_id BIGINT UNSIGNED NOT NULL,
  old_volume_m3 DECIMAL(8,2) NOT NULL,
  new_volume_m3 DECIMAL(8,2) NOT NULL,
  changed_by BIGINT UNSIGNED NOT NULL,
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_load_revision_load (production_load_id, changed_at),
  KEY idx_load_revision_changed_by (changed_by),
  CONSTRAINT fk_load_revision_load FOREIGN KEY (production_load_id) REFERENCES qbook_production_loads(id),
  CONSTRAINT fk_load_revision_user FOREIGN KEY (changed_by) REFERENCES qbook_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qbook_production_signoffs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_session_id BIGINT UNSIGNED NOT NULL,
  representative_name VARCHAR(150) NOT NULL,
  signature_mime VARCHAR(50) NOT NULL,
  signature_data MEDIUMBLOB NOT NULL,
  signature_sha256 CHAR(64) NOT NULL,
  load_count INT UNSIGNED NOT NULL,
  total_m3 DECIMAL(10,2) NOT NULL,
  signed_at DATETIME NOT NULL,
  signed_by_user_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_production_signoff_session (production_session_id),
  KEY idx_production_signoff_signed_by (signed_by_user_id),
  CONSTRAINT fk_production_signoff_session FOREIGN KEY (production_session_id)
    REFERENCES qbook_production_sessions(id),
  CONSTRAINT fk_production_signoff_user FOREIGN KEY (signed_by_user_id) REFERENCES qbook_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
