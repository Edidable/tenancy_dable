# Phase 02 — Configuration + Current + Errors + Railtie

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify the harness (Phase 01) boots before starting.

## Objective
Implement the configuration DSL, the `Current` attributes, the error hierarchy, the railtie, and the `TenancyDable` facade.

## Files
- `lib/tenancy_dable/configuration.rb` — every setting + default from the contract table; `ConfigurationError` on bad role/model config.
- `lib/tenancy_dable/current.rb` — `Current < ActiveSupport::CurrentAttributes`, `attribute :tenant, :membership, :tenant_scope_disabled`.
- `lib/tenancy_dable/errors.rb` — all error classes < `TenancyDable::Error`.
- `lib/tenancy_dable/railtie.rb` — require submodules; `ActiveSupport.on_load(:active_record/:action_controller)` wiring stubs.
- Update `lib/tenancy_dable.rb` facade: `.configure`, `.configuration`, `.current_tenant(=)`, `.current_membership(=)`, `.with_tenant`, `.without_tenant`. `current_tenant=` runs the **audit-override** check (`:log/:raise/:ignore`) and fires the **RLS hook** when `config.rls`.

## Acceptance
- Defaults match the contract table exactly.
- `with_tenant`/`without_tenant` save & restore prior state (ensure-block).
- Setting current_tenant to a different tenant triggers configured audit behavior.

## Validation
`bundle exec standardrb` + `bundle exec rspec` (smoke green).

## On completion
Scratchpad: the facade surface + audit/RLS hook behavior.
