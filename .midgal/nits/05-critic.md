# Nits Phase 05 — Critic / verify (final gate)

**Read `.midgal/NITS_PLAN.md` + `DESIGN.md`.** Final adversarial + consistency pass for the v0.2.0 delta. Be skeptical; prove the fixes, don't assume.

## Tasks
1. **Full gate green:** `bundle exec rake` (rspec + Standard) — zero failures, zero offenses.
2. **Fix A proof:** the generated `application_policy.rb` template contains `Context = TenancyDable::Policy::Context`; a generator spec asserts it. (Bonus: a spec that loads the rendered template and checks `ApplicationPolicy::Context` resolves to `TenancyDable::Policy::Context`.)
3. **Fix B proof:** all three `on_not_a_member` modes behave (default `NotAMemberError`; `:not_authorized` → `Pundit::NotAuthorizedError`; callable invoked in controller ctx). `validate!` rejects an unknown symbol. Default path is byte-for-byte the old behavior (no regression in existing resolution specs).
4. **Fix C proof:** `CrossTenantError::MESSAGE` exists, `Scoped` references it, the string is unchanged, and the red-team/cross-tenant specs still pass. No remaining hardcoded "belongs to a different tenant" literal in `lib/` except the constant definition (`grep`).
5. **No regressions to the six security invariants** — re-run `spec/security/red_team_spec.rb`; all pass.
6. **Contract consistency:** `spec/contract_spec.rb` reflects 14 settings + the new constant; error count still 8; version is `0.2.0` in version.rb + CHANGELOG.
7. Write `NITS_REPORT.md`: per-fix proof, full suite count, and confirm everything is committed on `nits/v0.2.0` (NOT master) for review.

## Validation
`bundle exec rake`.

## On completion
Scratchpad: pass/fail per fix + the final suite count + branch confirmation.
