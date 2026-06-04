# Phase 08 — Specs: Scoping Engine

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 03 (`scoped.rb`, `relation_extension.rb`) + Phase 01 harness exist.

## Files
`spec/scoping/*_spec.rb` against the Combustion `Widget` model. Cover, each as its own example:
- default scope filters to `current_tenant`; rows from another tenant are excluded.
- **fail-open** when `require_tenant` falsy + no tenant → returns all.
- **fail-closed** when `require_tenant` truthy + no tenant + not unscoped → raises `NoTenantError`.
- `without_tenant { }` disables scoping; restores after.
- auto-assign `tenant_id` on create from `current_tenant`.
- `tenant_id` immutable → reassign on persisted raises `TenantImmutableError`.
- bulk-write guard: `update_all`/`delete_all`/`destroy_all` raise `BulkWriteError` with no/mismatched tenant; allowed under `without_tenant`.
- cross-tenant `belongs_to` validation rejects an association from another tenant.
- `validates_uniqueness_to_tenant` scopes uniqueness per tenant.
- RLS hook: with `config.rls = true`, setting current_tenant executes `rls_statement` (assert via a connection spy/stub).

## Validation
`bundle exec rspec spec/scoping`.

## On completion
Scratchpad: coverage list + any edge cases found.
