# Phase 03 — Scoping Engine (self-contained)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify configuration/current/errors (Phase 02) exist before starting. **No `acts_as_tenant` dependency** — implement the core here.

## Files
- `lib/tenancy_dable/scoped.rb` — `TenancyDable::Scoped` concern with `belongs_to_tenant(name = :tenant, **opts)`:
  - association + `tenant_scoped?` predicate.
  - `default_scope`: `tenant_scope_disabled` → `all`; `current_tenant` → `where(fk => id)`; else if `require_tenant` truthy in ctx → **raise `NoTenantError`**; else `all`.
  - auto-assign fk on create when blank; **immutable** fk after persist (raise `TenantImmutableError`); cross-tenant `belongs_to` validation (`CrossTenantError` message); `validates_uniqueness_to_tenant`.
- `lib/tenancy_dable/relation_extension.rb` — prepend to `ActiveRecord::Relation`; `update_all`/`delete_all`/`destroy_all` raise `BulkWriteError` for scoped models with no/again-mismatched tenant; bypass under `without_tenant`.
- Wire both into the railtie; make the Combustion `Widget` model `include TenancyDable::Scoped` + `belongs_to_tenant`.

## Acceptance
- Matches the contract's Scoping section line-for-line.
- `Widget` boots and is tenant-scoped in the harness.

## Validation
`bundle exec standardrb` (specs land in Phase 08; do a boot check via `bundle exec rspec` smoke).

## On completion
Scratchpad: the exact fail-closed decision tree + bulk-write guard rules.
