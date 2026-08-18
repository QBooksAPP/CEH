# Database Migration Work

The repository currently contains only `Server/migration_v1_1.sql`, which
creates the authentication-token table. It is not a complete schema and must
not be presented as sufficient to reproduce production.

A future migration project should begin from a reviewed production schema
export with data removed. It should define the existing tables, foreign keys,
indexes, status constraints and audit/history relationships without guessing
types or defaults from PHP queries.

The reviewed schema should also enforce the CEH invariant that every Mix Design
has a batch volume of exactly 1.0000 m³. Subject to the actual production column
type and database version, the intended outcome is:

- a default of `1.0000` for `qbook_mix_designs.batch_volume_m3`; and
- a database constraint rejecting values other than `1.0000`.

Do not apply that change directly to production. Create, review and test the
complete migration against a disposable database first, including an audit of
existing rows that would violate the constraint.
# Build 41: exact calibration revision snapshots (not applied)

`Server/migration_v1_2_settings_calibration_revision.sql` adds
`qbook_production_settings.calibration_revision_no`. The existing
`calibration_id` remains the selected calibration reference. The revision
column is required because an approved calibration can later be reopened and
revised under the same ID; without a snapshot column, old Settings History
cannot prove which revision was used.

Existing snapshots are backfilled from their currently referenced calibration
as the best available historical value. Deploy the migration before or
together with the Build 41 PHP files; do not deploy `settings_apply.php` first.
