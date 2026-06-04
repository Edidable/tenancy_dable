# Phase 09 — Specs: Identity, Roles, Last-Owner Guard

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 04 (identity concerns) + harness exist.

## Files
`spec/identity/*_spec.rb`:
- role predicates generated from `config.roles` (`owner?`/`admin?`/`member?`).
- `Membership` role inclusion validation; `[user_id, tenant_id]` uniqueness.
- **last-owner guard**: demoting the only owner is blocked (`throw :abort`, record invalid/unsaved); demoting a non-last owner succeeds.
- `manager?` true for owner+admin, false for member.
- `User#membership_for(tenant)` / `#member_of?(tenant)` correctness (incl. nil/non-member).
- `Tenant#owners` returns owner users; slug auto-generation + uniqueness + format validation.
- `Membership` does NOT respond to a tenant default scope (assert it is queryable without `current_tenant`).

## Validation
`bundle exec rspec spec/identity`.

## On completion
Scratchpad: guard semantics + any role-config edge cases.
