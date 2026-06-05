# Nits Phase 02 — Fix B: host-selectable not-a-member behavior

**Read `.midgal/NITS_PLAN.md` (Fix B) and the phase-00 scratchpad** for the pinned setting name/values. Verify phase 00 (DESIGN delta) landed first.

## Files
- `lib/tenancy_dable/configuration.rb`:
  - add `attr_accessor :on_not_a_member`; default `@on_not_a_member = :not_a_member_error`.
  - in `validate!`: if `on_not_a_member` is a Symbol, it must be `:not_a_member_error` or `:not_authorized` (else `ConfigurationError`); a callable is accepted as-is.
- `lib/tenancy_dable/controller/resolvable.rb`: in `tenancy_dable_resolve_tenant`, replace the unconditional `raise NotAMemberError` (membership nil branch) with a dispatch:
  - `:not_a_member_error` → `raise TenancyDable::NotAMemberError, "..."` (today's message).
  - `:not_authorized` → `require "pundit"` lazily then `raise Pundit::NotAuthorizedError`.
  - callable → `instance_exec(tenant, &setting)` (runs in controller context; host may redirect / head :forbidden / raise its own).
  Keep the slug-only + membership-required semantics otherwise identical.
- `lib/generators/tenancy_dable/install/templates/initializer.rb.tt`: document the new setting (all three forms), commented with its default.
- `spec/resolution/membership_enforcement_spec.rb` (extend) or a new `spec/resolution/not_a_member_behavior_spec.rb`: cover all three modes — default raises `NotAMemberError`; `:not_authorized` raises `Pundit::NotAuthorizedError`; a callable is invoked in controller context and its outcome wins.
- `spec/contract_spec.rb`: add `on_not_a_member` (default `:not_a_member_error`) to the locked settings list; bump the settings count to 14.

## Acceptance / Validation
- `bundle exec rspec spec/resolution spec/contract_spec.rb` green.
- Default behavior unchanged (non-members still get `NotAMemberError` out of the box).

## On completion
Scratchpad: the three modes + how the callable is invoked.
