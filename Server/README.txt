CEH PHP API

Runtime configuration:
- Copy config.example.php to config.php in the runtime environment.
- Supply credentials through the protected runtime copy.
- config.php is ignored by Git and must never be committed or exposed.

Canonical calibration calculation:
- calibration_math.php
- calibration_save.php
- calibration_calculate.php delegates to calibration_math.php

Canonical Production Settings:
- settings_engine.php
- settings_preview.php
- settings_apply.php

Legacy compatibility:
- production_settings.php is deprecated and retained only until production
  access logs confirm that it is unused.

Development-only:
- development/login_debug.php must not be served in production. It also refuses
  requests unless the configured environment is exactly "development".

Deployment:
- Do not serve config.php, config.example.php, development/, SQL, documentation,
  logs, dumps or backup files from the public web root.
- health.php intentionally returns only minimal availability information.
- The repository does not yet include the complete production database schema.
  See docs/DATABASE_MIGRATIONS.md in the repository root.

Signed Production Reports:
- Apply migration_v1_6_production_reports.sql before deploying the updated
  production_session_sign.php or production_report_pdf.php.
- Deploy production_report_common.php, production_report_pdf.php,
  assets/ceh_logo.png and the complete pinned vendor/tcpdf directory together.
- Reports are generated in memory; do not add a writable/public reports folder.
