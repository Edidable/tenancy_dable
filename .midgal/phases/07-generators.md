# Phase 07 — Generators (install + model)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phases 02–06 exist (the generator wires them into a host app).

## Files
- `lib/generators/tenancy_dable/install/install_generator.rb` (+ `templates/`):
  - `config/initializers/tenancy_dable.rb` (commented full DSL).
  - migrations: `create_tenants` (slug unique), `create_memberships` (user_id, tenant_id, role, unique [user_id, tenant_id]).
  - `app/policies/application_policy.rb < TenancyDable::Policy::Base`.
  - a `Current` attributes file or clear instructions; a route-scaffold comment block for `scope "/:tenant_slug"`.
  - if `Tenant`/`User`/`Membership` exist, print include instructions; else offer to generate them.
  - **idempotent** — safe to re-run (skip existing).
- `lib/generators/tenancy_dable/model/model_generator.rb` (+ templates): generate a tenant-scoped model (`include TenancyDable::Scoped` + `belongs_to_tenant`) + migration with `tenant_id` + index.

## Acceptance
- `install` produces the files above; re-running doesn't duplicate.
- `model Widget name:string` produces a scoped model + migration.

## Validation
`bundle exec standardrb`.

## On completion
Scratchpad: generated file inventory + idempotency approach.
