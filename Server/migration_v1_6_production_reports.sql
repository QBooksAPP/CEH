-- NOT APPLIED TO PRODUCTION. Apply only after v1.5 and before deploying
-- the Signed Production Report PHP files and TCPDF vendor directory.
--
-- Test report rows may be removed only by a separately reviewed go-live
-- cleanup after a fresh backup. Once live operations begin, report numbers
-- must never be reset, reused, deleted, or renumbered.

CREATE TABLE qbook_production_reports (
  report_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_session_id BIGINT UNSIGNED NOT NULL,
  issued_at DATETIME NOT NULL,
  PRIMARY KEY (report_no),
  UNIQUE KEY uq_production_report_session (production_session_id),
  CONSTRAINT fk_production_report_session
    FOREIGN KEY (production_session_id)
    REFERENCES qbook_production_sessions(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
