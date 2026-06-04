# Phase 06 — Authorization (Pundit Context + Base Policy)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 04 (identity) exists.

## Files
- `lib/tenancy_dable/policy/context.rb` — `TenancyDable::Policy::Context = Data.define(:user, :tenant, :membership)` with `#role`.
- `lib/tenancy_dable/policy/base.rb` — `TenancyDable::Policy::Base`:
  - secure-by-default actions (`index?/show?/create?/new?/update?/edit?/destroy?` → false; `new?`→`create?`, `edit?`→`update?`).
  - readers `user/tenant/membership/role`; helpers `same_tenant?` (`record.respond_to?(:tenant_id) && record.tenant_id == tenant&.id`), `owner?`, `manager?` (role ∈ manager_roles), `member?` (role present) — helpers **private** so pundit-matchers don't treat them as actions.
  - nested `Scope`: `resolve` → `scope.none` when tenant nil, else `scope.where(config.tenant_fk => tenant.id)`.
- Provide `TenancyDable.pundit_context(user:, tenant:, membership:)` builder.

## Acceptance
- Matches the in-house ApplicationPolicy semantics (Context, not raw user).
- Scope fails closed with no tenant.

## Validation
`bundle exec standardrb`.

## On completion
Scratchpad: the Context shape + capability helper rules.
