# Nits Phase 01 — Fix A: ApplicationPolicy Context alias

**Read `.midgal/NITS_PLAN.md` (Fix A).** Generator/template change only — no runtime lib change.

## Files
- `lib/generators/tenancy_dable/install/templates/application_policy.rb.tt` — inside the generated `ApplicationPolicy < TenancyDable::Policy::Base`, add:
  ```ruby
  # So `ApplicationPolicy::Context` resolves (the constant lives in
  # TenancyDable::Policy, not in Base) — lets policy specs build the subject
  # as ApplicationPolicy::Context.new(...) or TenancyDable.pundit_context(...).
  Context = TenancyDable::Policy::Context
  ```
  and add a commented `pundit_user` example in the comment block pointing at
  `TenancyDable.pundit_context(user:, tenant:, membership:)`.
- `spec/generators/install_generator_spec.rb` — add an example asserting the generated
  `app/policies/application_policy.rb` contains `Context = TenancyDable::Policy::Context`.

## Acceptance / Validation
- `bundle exec rspec spec/generators` green (incl. the new assertion).
- Generator stays idempotent (don't change its skip-existing behavior).

## On completion
Scratchpad: confirm the alias is emitted and asserted.
