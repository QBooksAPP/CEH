# CEH Operations

CEH Operations is the mobile operations system for Concrete Equipment Hire
Limited. It consists of a Flutter Android application and a PHP/MySQL API.

## Project layout

- `lib/` — Flutter application, screens, models, API client and business logic.
- `test/` — Flutter unit and widget tests.
- `Server/` — PHP API source. Runtime database credentials are deliberately
  excluded from Git.
- `.github/workflows/build-apk.yml` — signed Android build and GitHub Release
  workflow.
- `docs/` — architecture, endpoint and database-migration notes.

## Roles

- **Operator** — enters calibration data, submits it for approval, views active
  Mix Designs and previews/applies production settings.
- **Supervisor** — has the operational endpoint access currently granted to
  operators.
- **Admin** — approves, rejects and reopens calibrations; creates and manages
  Mix Designs and admixtures; and views administrative history.

All permissions are enforced by the PHP API. Hiding an action in Flutter is not
treated as authorization.

## Calibration workflow

1. An operator selects a mixer, records the site in calibration notes, and
   enters up to six trials for each calibration section.
2. A draft may be saved and edited while its status is `DRAFT` or after it has
   been `REJECTED`.
3. Server-side calculation deducts container weight from every valid trial,
   applies moisture correction to stone and sand, and deducts the cement safety
   factor from cement results.
4. Cement FULL and the 5/8/11 cm stone and sand sections are required for
   submission. Cement HALF is optional.
5. Submission locks the draft and sends it to an Admin.
6. An Admin approves or rejects it. Only `APPROVED` calibration data can feed
   Production Settings.

## Mix Designs

Every design is expressed on a 1.0000 m³ basis. Fly ash is not used.

### CLIENT mode

The client supplies cement, sand, granite and water. CEH preserves those
material quantities. The API calculates absolute volume for Admin review, but
does not rebalance the client's sand quantity.

### CALCULATED mode

Admin supplies cement, granite, water, air and material specific gravities.
Sand fills the remaining absolute volume. Changing cement, granite, water, air
or a specific gravity recalculates sand so the design remains exactly 1.0 m³.

## Production Settings

The canonical implementation is:

- `Server/settings_engine.php` — calculation engine.
- `Server/settings_preview.php` — calculation without persistence.
- `Server/settings_apply.php` — server-side recalculation, saved snapshot and
  audit event.

It selects the latest approved calibration for the chosen mixer, calculates
cement counts, sand and granite gate positions, moisture-adjusted water flow,
production rate and active admixture flows. `Server/production_settings.php`
is retained only as a deprecated compatibility endpoint pending production
usage verification.

## Local backend configuration

Copy `Server/config.example.php` to `Server/config.php` and supply local/runtime
credentials. Never commit `Server/config.php`, `.env` files, private keys,
keystores, database dumps or logs.

The repository does not yet contain a complete database migration set. See
`docs/DATABASE_MIGRATIONS.md` before creating a new environment. Do not infer a
production schema from endpoint queries alone.

## Android build and updates

Every push to `main`, and every manual workflow dispatch, runs **Build CEH APK**.
The workflow:

1. Generates the Android project scaffolding.
2. Configures Android networking and the permanent signing key from GitHub
   Actions secrets.
3. Runs `flutter analyze` and `flutter test`.
4. Builds a signed release APK with the workflow run number as its build number.
5. Uploads `CEH.apk` as an artifact and publishes a `build-N` GitHub Release.

The app checks the latest GitHub Release and offers the `CEH.apk` asset when its
build number is newer than the installed build.

Signing keys and their passwords belong only in GitHub Actions secrets. They
must never be stored in this repository.

## Production deployment notes

- Deploy PHP changes separately from the Flutter APK.
- Provide `Server/config.php` securely on the server; do not deploy the example
  as live configuration.
- Do not expose `Server/development/`, SQL files, documentation, configuration
  or backups through the web server.
- Remove the old root-level `login_debug.php` from the server during a future
  controlled deployment; uploading this repository alone will not delete it.
- Restrict the health endpoint as appropriate for the production monitor.
- Verify production traffic no longer uses deprecated endpoints before removal.
- Back up and migrate the database through a reviewed migration process. This
  repository does not currently define the complete production schema.

See [Architecture and Development](docs/ARCHITECTURE.md) for the endpoint map
and implementation boundaries.
