# Architecture and Development

## Runtime flow

The Flutter app communicates with `https://qbook.concretehireng.com` using JSON
over HTTPS. Login returns a bearer token, which Flutter stores using secure
platform storage and sends in the `Authorization` header.

PHP endpoints load `bootstrap.php` for configuration/database access and
`auth.php` for bearer authentication, role checks and auditing. MySQL stores
users, token hashes, mixers, calibrations, Mix Designs and production snapshots.

## Endpoints currently connected to Flutter

| Endpoint | Purpose | Roles |
|---|---|---|
| `login.php` | Authenticate | Public |
| `mixers.php` | Active mixer list | Admin, Supervisor, Operator, Viewer |
| `calibration_save.php` | Save draft and recalculate | Admin, Supervisor, Operator |
| `calibration_submit.php` | Validate and submit | Admin, Supervisor, Operator |
| `calibration_admin_list.php` | Review queue and approved list | Admin |
| `calibration_review.php` | Approve or reject | Admin |
| `calibration_reopen.php` | Return approved record to submitted | Admin |
| `calibration_data.php` | Approved read-only calibration data | Admin, Supervisor, Operator |

`calibration_math.php` is the canonical calibration formula implementation.
`calibration_calculate.php` remains compatible as a separate endpoint but now
delegates calculation to that helper rather than maintaining alternate maths.

## Mix Design endpoints

- `mix_designs.php` — list; non-admin roles receive active designs only.
- `mix_design_get.php` — Admin detail view.
- `mix_design_create.php` — Admin create.
- `mix_design_update.php` — Admin update/version/activation management.
- `mix_admixture_create.php` — Admin create.
- `mix_admixture_update.php` — Admin update/activation management.

CLIENT designs preserve all client material quantities. CALCULATED designs use
the absolute-volume method to balance sand to 1.0000 m³. Fly ash is excluded.

## Canonical Production Settings endpoints

- `settings_engine.php` owns all calculations and approved-calibration lookup.
- `settings_preview.php` calculates a read-only preview.
- `settings_apply.php` recalculates without trusting client-calculated values,
  persists an immutable snapshot and records an audit event.
- `production_settings_history.php` returns Admin history.

`production_settings.php` is legacy/deprecated. Do not connect new clients to
it. Retain it until production access logs confirm it is unused.

## Legacy and administrative endpoints

The older split calibration endpoints (`calibration_create.php`,
`calibration_save_trials.php`, `calibration_calculate.php`,
`calibration_pending.php`) are not called by the current Flutter app. The
history, user and audit endpoints are likewise not connected yet.

`development/login_debug.php` is development-only, guarded by the configured
environment, and must not be served in production.

## Security boundaries

- `Server/config.php` is runtime-only and ignored by Git.
- `Server/config.example.php` contains placeholders and is safe to version.
- Do not serve configuration, development tools, SQL, logs, dumps or docs from
  the public API directory.
- GitHub Actions signing material must exist only as repository secrets.
- API role checks are authoritative; Flutter visibility checks are convenience
  only.

## Development checks

Run these before review when the necessary runtimes are installed:

```text
flutter analyze
flutter test
php -l Server/<file>.php
```

PHP integration tests require a disposable database with reviewed migrations;
never run them against production.
# Build #42 production log

Concrete Operations is divided into Calibration and Production. Operators use the operational **Mixer Settings** view; Admin retains the detailed **Mix Design Settings** view and calibration-source override. `settings_engine.php`, `settings_preview.php`, and `settings_apply.php` remain the canonical calculation path and their formulas are unchanged.

Production Log uses `production_sessions.php`, `production_session_create.php`, `production_session_get.php`, `production_load_save.php`, and `production_session_sign.php`. Session identity fields are snapshots because no suitable Client/Project master tables currently exist. Operator ownership and OPEN/SIGNED state are enforced by PHP. Sign-off locks the session and calculates authoritative load count/total inside a database transaction.

Signatures are PNG binaries stored in `qbook_production_signoffs.signature_data` with a SHA-256 digest. For the current application size this avoids publicly addressable signature files and hosting-path assumptions. The trade-off is database growth; protected object/file storage can replace it later behind the same authenticated endpoint if volume warrants it.

Production Log endpoints set their PDO session to `+00:00` before reading or
writing log records. This makes MySQL defaults and automatic update timestamps
UTC without changing unrelated legacy endpoint behaviour. Flutter treats these
backend date-times as UTC and renders them in the device's local timezone.

## Signed Production Reports

`production_report_pdf.php` is an authenticated binary endpoint for SIGNED
sessions. It reuses the Production Log ownership rule (an Operator's own
sessions, or every session for Admin), reads the immutable sign-off load count
and total, embeds the stored PNG signature, and streams a PDF generated in
memory. No PDF or signature is written to a public path.

`qbook_production_reports.report_no` supplies the independent permanent
sequence formatted as `CEH-PR-000001`. The one-to-one unique session key makes
repeated downloads idempotent. New numbers are allocated in the sign-off
transaction; the PDF endpoint can allocate a number lazily for a signed session
created before v1.6 was deployed.

TCPDF 6.11.3 is pinned under `Server/vendor/tcpdf` (LGPL-3.0-or-later). The CEH
renderer uses direct cells, local PNG images and bundled DejaVu fonts. It does
not use optional mbstring-dependent transformations. TCPDF's cURL options are
initialized only inside its optional remote-resource functions. CEH uses no
remote resources, so the report endpoint requires zlib and a PNG image engine
(GD is available in production), but not cURL or mbstring.
