# Company regional-settings foundation

This phase associates authenticated users with one company and gives that
company an audited regional configuration. It does **not** provide tenant
isolation: existing operational and accounting tables remain implicitly owned
by CEH/company 1 until a future controlled isolation phase.

## Date and timestamp semantics

- API date-only values remain canonical `YYYY-MM-DD`. They are formatted for
  display without timezone conversion.
- Explicit `Z` or offset-aware event timestamps represent instants and are
  converted with the company's IANA timezone, including daylight-saving rules.
- Historical `DATETIME` values with no offset have ambiguous provenance. They
  retain their stored wall-clock components and are not reinterpreted as UTC.
- New server event writes continue to use the existing UTC convention. APIs
  should expose an explicit UTC suffix/offset as endpoints are safely revised.

## Currency boundary

Base currency controls presentation and the denomination of future company
accounting. It does not perform FX conversion. CEH's NGN base currency is
locked once posted financial activity exists; changing it requires a separate
controlled migration.

Invoices snapshot currency at Issue, Estimates at Send, and Client Payments at
Post. Pre-v1.21 immutable documents with a null snapshot are explicitly treated
as legacy NGN and never inherit a later company setting.
