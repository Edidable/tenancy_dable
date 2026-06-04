# Phase 13 — Integration Spec (end-to-end)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify all code phases (02–07) and their specs (08–12) are green.

## Files
`spec/integration/*_spec.rb` — exercise the layers together through the Combustion app:
- two tenants (A, B), two users, memberships; seed widgets in each.
- **isolation**: acting in A, a query for widgets never returns B's rows; flipping `current_tenant` flips the visible set.
- **resolution + policy together**: resolve `/:slug`, then a `Policy::Scope` returns only the active tenant's rows; a member of B hitting A's slug is rejected.
- **ActiveJob propagation**: enqueue a job under tenant A; on perform, `current_tenant` is restored to A (serialize/deserialize round-trip). Implement a tiny `ApplicationJob`-style propagation include if the contract requires it; assert it here.
- **bulk-write guard** surfaces in a realistic flow (mass update blocked without scope).
- **RLS toggle**: with `config.rls = true`, the `rls_statement` runs on tenant switch; with it false, it does not.

## Validation
`bundle exec rspec spec/integration`.

## On completion
Scratchpad: the end-to-end isolation proof + any gap found (feeds Phase 15).
