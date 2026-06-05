# v0.3 Phase 00 — Contract delta → DESIGN.md

**Read `.midgal/V03_PLAN.md` (authoritative) + `.midgal/PLAN.md` + `DESIGN.md`.** Doc-only phase; no lib changes. Respect the OUT-of-scope guardrails in V03_PLAN (gem only; gem does not own Cable auth; keep inherent Job seams).

## Tasks
1. Add a `DESIGN.md` section for `TenancyDable::Channel` (opt-in, Action Cable parallel to `Controller::Resolvable`): the frozen helpers (`current_tenant`, `current_membership`, `tenant_member?`, `reject_unless_member!`, `stream_for_tenant`, `with_tenant_context`), the auto-wrapped `perform_action`, slug-only resolution, membership enforcement, and that it READS `current_user` from the connection (host owns auth via `identified_by :current_user`).
2. Document the `TenancyDable::Job` membership field (`tenancy_dable_membership_id`) and that `perform` now restores `current_membership` too; note the inherent enqueue-time/deleted-tenant seams are unchanged.
3. Record version target `0.3.0`; both features additive; Action Cable optional (opt-in require).
4. Do not change any frozen signature, default, the 8-error count, or settings count.

## Acceptance / Validation
- `grep -q "TenancyDable::Channel" DESIGN.md`
- `bundle exec rspec` still green (no code changed).

## On completion
Scratchpad: the pinned Channel helper names + the Job membership key, so later phases match.
