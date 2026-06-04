# Phase 11 — Specs: Authorization (Pundit)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 06 (`Policy::Context`, `Policy::Base`) + harness exist.

## Files
`spec/policy/*_spec.rb` (use pundit-matchers if available, else plain expectations):
- `Context#role` derives from membership; nil membership → nil role.
- secure-by-default: a bare subclass of `Policy::Base` forbids all actions.
- `same_tenant?`: true only when `record.tenant_id == tenant.id`; false across tenants and when tenant nil.
- `owner?` / `manager?` (owner+admin) / `member?` capability matrix across roles.
- `Scope#resolve`: returns `scope.none` when tenant nil; filters by `tenant_fk` otherwise; excludes other tenants' rows.
- a sample concrete policy (e.g. `WidgetPolicy < ...Base`) exercising read=member, mutate=manager + same_tenant.

## Validation
`bundle exec rspec spec/policy`.

## On completion
Scratchpad: the capability matrix asserted.
