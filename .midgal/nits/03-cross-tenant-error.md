# Nits Phase 03 — Fix C: CrossTenantError is no longer dead

**Read `.midgal/NITS_PLAN.md` (Fix C).** Keep the class (removing it would break the frozen 8-error contract); make it the message's single source of truth.

## Files
- `lib/tenancy_dable/errors.rb`: give `CrossTenantError` a constant:
  ```ruby
  class CrossTenantError < Error
    MESSAGE = "belongs to a different tenant"
  end
  ```
  (keep its doc comment; it remains a `< Error` subclass — count stays 8).
- `lib/tenancy_dable/scoped.rb`: in the cross-tenant `belongs_to` validation, replace the hardcoded
  `errors.add(reflection.name, "belongs to a different tenant")` with
  `errors.add(reflection.name, TenancyDable::CrossTenantError::MESSAGE)`.
  **Do not change the string value** — existing specs (`spec/scoping/cross_tenant_spec.rb`,
  `spec/security/red_team_spec.rb`) assert `"belongs to a different tenant"`; they must keep passing.
  The validation still ADDS an error (does not raise) — Rails validation semantics are unchanged.
- `spec/scoping/cross_tenant_spec.rb` (extend): add one example asserting the message equals
  `TenancyDable::CrossTenantError::MESSAGE` (proves the class is now wired, not dead).

## Acceptance / Validation
- `bundle exec rspec spec/scoping` green (existing + new).

## On completion
Scratchpad: confirm the message constant is the single source and referenced from Scoped.
