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
