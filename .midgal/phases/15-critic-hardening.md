# Phase 15 — Critic / Hardening (adversarial)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** This is the final gate. Be adversarial — try to break tenant isolation.

## Tasks
1. **Full gate green:** `bundle exec rake` (rspec + standard) passes with zero failures/offenses.
2. **Security audit against the 6 invariants** in `PLAN.md`. For each, either point to the proving spec or add a new red-team spec:
   - prove fail-closed actually raises (not silently `all`).
   - attempt a cross-tenant read three ways (direct query, association, bulk-write) — all blocked.
   - prove `tenant_id` immutability.
   - prove Pundit scope returns `none` with no tenant.
   - prove slug-only resolution (id in slug slot does not resolve).
   - grep for any log line that could carry payloads/PII (only tenant ids allowed).
3. **API-vs-contract diff:** every symbol in `PLAN.md`'s contract exists with the right signature; flag any drift.
4. Bump `TenancyDable::VERSION` to `0.1.0`; ensure CHANGELOG matches.
5. Write `FINAL_REPORT.md`: what shipped, invariant proofs, coverage summary, any TODO/deferred seams.

## Validation
`bundle exec rake`.

## On completion
Scratchpad: pass/fail per invariant + the final report location.
