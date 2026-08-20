-- NOT APPLIED TO PRODUCTION. Take a fresh backup and review before applying.
-- Apply after migration_v1_8_project_mixer_allocation.sql.

ALTER TABLE qbook_clients
  ADD COLUMN archived_at DATETIME NULL AFTER is_active,
  ADD COLUMN archived_by BIGINT UNSIGNED NULL AFTER archived_at,
  ADD KEY idx_clients_archive_name (archived_at, name),
  ADD KEY idx_clients_archived_by (archived_by),
  ADD CONSTRAINT fk_clients_archived_by FOREIGN KEY (archived_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE qbook_projects
  ADD COLUMN archived_at DATETIME NULL AFTER is_active,
  ADD COLUMN archived_by BIGINT UNSIGNED NULL AFTER archived_at,
  ADD KEY idx_projects_archive_client (archived_at, client_id, name),
  ADD KEY idx_projects_archived_by (archived_by),
  ADD CONSTRAINT fk_projects_archived_by FOREIGN KEY (archived_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE qbook_calibrations
  ADD COLUMN archived_at DATETIME NULL AFTER status,
  ADD COLUMN archived_by BIGINT UNSIGNED NULL AFTER archived_at,
  ADD KEY idx_calibrations_archive_context
    (archived_at, client_id, project_id, mixer_id, stone_size, status),
  ADD KEY idx_calibrations_archived_by (archived_by),
  ADD CONSTRAINT fk_calibrations_archived_by FOREIGN KEY (archived_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE qbook_mix_designs
  ADD COLUMN archived_at DATETIME NULL AFTER is_active,
  ADD COLUMN archived_by BIGINT UNSIGNED NULL AFTER archived_at,
  ADD KEY idx_mix_designs_archive_context
    (archived_at, client_id, project_id, stone_size, is_active),
  ADD KEY idx_mix_designs_archived_by (archived_by),
  ADD CONSTRAINT fk_mix_designs_archived_by FOREIGN KEY (archived_by)
    REFERENCES qbook_users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

-- Existing inactive Clients, Projects and Mix Designs stay inactive. Their
-- historical state is not guessed by inventing archive timestamps.
