-- NOT APPLIED TO PRODUCTION. Back up and review before deployment.
ALTER TABLE qbook_production_settings
  ADD COLUMN calibration_revision_no INT NOT NULL DEFAULT 1 AFTER calibration_id;

-- Existing snapshots predate this column. Backfill from the referenced row as
-- the best available historical value; future Apply operations store it exactly.
UPDATE qbook_production_settings ps
JOIN qbook_calibrations c ON c.id = ps.calibration_id
SET ps.calibration_revision_no = c.revision_no;
