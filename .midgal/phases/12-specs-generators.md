# Phase 12 — Specs: Generators

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 07 (generators) + harness exist.

## Files
`spec/generators/*_spec.rb` (Rails generator testing — `Rails::Generators::TestCase` wrapped in RSpec or `generator_spec`):
- `tenancy_dable:install` creates the initializer, the `tenants` + `memberships` migrations, and `app/policies/application_policy.rb < TenancyDable::Policy::Base`.
- install is **idempotent**: a second run adds no duplicates and does not crash.
- `tenancy_dable:model Widget name:string` creates a model that `include`s `TenancyDable::Scoped` with `belongs_to_tenant`, plus a migration with `tenant_id` + index.
- generated migration content is valid Ruby and references the configured `tenant_fk`.

## Validation
`bundle exec rspec spec/generators`.

## On completion
Scratchpad: generator test approach + destination-root cleanup.
