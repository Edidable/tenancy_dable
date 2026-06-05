# Nits Phase 00 — Decision delta → DESIGN.md

**Read `.midgal/NITS_PLAN.md` (authoritative for this run) and `.midgal/PLAN.md` + `DESIGN.md`.** No lib code changes in this phase — update the contract doc so later phases implement against it.

## Tasks
1. In `DESIGN.md`, amend the Configuration section (§4.1) to add the new setting:
   - `on_not_a_member` — default `:not_a_member_error`; accepts `:not_a_member_error`, `:not_authorized`, or a callable `->(tenant)`. Document the exact semantics from NITS_PLAN Fix B.
   - Note the settings count is now **14**.
2. Note `CrossTenantError::MESSAGE` as an additive constant (Fix C) and that the cross-tenant validation sources its message from it.
3. Note the generated `ApplicationPolicy` now defines `Context = TenancyDable::Policy::Context` (Fix A) — a generator/template change, not a runtime-surface change.
4. Record the version bump target `0.2.0` and that all three fixes are additive (default behavior unchanged).
5. Do NOT change any frozen signature, the error count (stays 8 classes), or any default that would alter isolation.

## Acceptance / Validation
- `grep -q "on_not_a_member" DESIGN.md`
- `bundle exec rspec` still green (no code changed yet).

## On completion
Scratchpad: the exact setting name/values pinned, so phases 01–03 match.
