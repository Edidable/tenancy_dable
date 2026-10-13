---
paths:
  - "lib/tenancy_dable/errors.rb"
---
Every gem error descends from `TenancyDable::Error`; `spec/contract_spec.rb` ("Error hierarchy") locks the list of names. Never inherit from `StandardError` or an Active Record class directly.
`errors.rb` has no dependencies and loads before every other unit; do not require other gem files from it.
Messages and events carry identifiers only (model names, tenant ids, and the tenant slug a request named in `NotAMemberError`), never a record or its attributes; `ConfigurationError` names the offending setting value.
`CrossTenantError` is never raised; it exists for `CrossTenantError::MESSAGE`, which must equal the `en` `cross_tenant` locale text. The cross-tenant `belongs_to` check adds a validation error with the `:cross_tenant` key, so its text comes from the locale files and a host override wins.
`TenantNotFoundError` is raised by `Job` for a vanished tenant, not by slug resolution; an unknown slug raises `ActiveRecord::RecordNotFound` under `on_tenant_not_found = :raise`.
`ConfigurationError` covers both `Configuration#validate!` and invalid or repeated declarations; both are boot or class-load misconfiguration.
Foreign-tenant writes, reads and bulk writes raise (`CrossTenantWriteError`, `CrossTenantReadError`, `BulkWriteError`); do not turn them into validation errors.
Adding an error: also `spec/contract_spec.rb` (names list and title), the README `## Errors` table, the error counts in `DESIGN.md`, a spec that triggers the raise, the initializer template comment if a setting governs it, `docs/domains/errors.md`.
Changing which error a guard raises is a breaking change: update the README table, `UPGRADING.md` and the specs that assert the class.
Narrative: docs/domains/errors.md
