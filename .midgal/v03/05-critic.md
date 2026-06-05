# v0.3 Phase 05 — Critic / verify (final gate)

**Read `.midgal/V03_PLAN.md` + `DESIGN.md`.** Final adversarial + consistency pass for v0.3.0. Be skeptical; prove the features and the absence of regressions.

## Tasks
1. **Full gate green:** `bundle exec rake` (rspec + Standard) — zero failures, zero offenses.
2. **Action Cable proofs** (from `spec/channels`): member subscribes + streams `tenant:<id>`; non-member rejected; unknown slug rejected; a channel action is tenant-scoped (cross-tenant rows invisible) and leaves no context leak. Add any missing adversarial case (e.g. a member of tenant B cannot subscribe to tenant A's channel).
3. **Job membership proof:** `perform` restores both tenant and membership; backward-compatible with a membership-less payload; no leak after perform. Tenant-only propagation still works.
4. **Guardrails held:** confirm NO host/skeleton file was touched (work is entirely under the gem repo); confirm the gem did NOT add cookie/session/auth parsing to the Channel concern (it reads `current_user` only); confirm the inherent Job seams (enqueue-time capture, deleted-tenant fail-open) are unchanged.
5. **No regressions to the six security invariants** — re-run `spec/security/red_team_spec.rb`; all pass. Slug-only still holds for the new Channel path.
6. **Contract consistency:** `spec/contract_spec.rb` includes `TenancyDable::Channel`; error count 8; version `0.3.0` in version.rb + CHANGELOG.
7. Append to `FINAL_REPORT.md` (or write `V03_REPORT.md`): per-feature proof, full suite count, and confirm everything is committed on `feat/v0.3.0-action-cable` (NOT master).

## Validation
`bundle exec rake`.

## On completion
Scratchpad: pass/fail per feature + final suite count + branch confirmation.
