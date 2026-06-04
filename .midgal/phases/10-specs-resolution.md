# Phase 10 — Specs: Slug Resolution (request/controller)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 05 (`Resolvable` + Combustion `WidgetsController`/route) + harness exist.

## Files
`spec/resolution/*_spec.rb` (request specs through the Combustion app):
- valid `/:tenant_slug` + acting user who is a member → sets `current_tenant` + `current_membership`.
- unknown slug → honors `on_tenant_not_found` (`:raise` → `ActiveRecord::RecordNotFound`; `:null` → nil tenant).
- authenticated user who is NOT a member of the resolved tenant → raises `NotAMemberError`.
- `default_url_options` injects the active slug so path helpers omit it.
- resolution uses slug only — a numeric id in the slug position does not resolve a tenant by id.

## Validation
`bundle exec rspec spec/resolution`.

## On completion
Scratchpad: how the acting user is stubbed via `current_user_resolver` in specs.
