# Phase 00 — Contract Freeze → DESIGN.md

**Read `.midgal/PLAN.md` first — it is the frozen contract. This phase writes no production code.**

## Objective
Expand the frozen contract in `PLAN.md` into a worker-facing `DESIGN.md` at the repo root that every later phase implements against verbatim.

## Tasks
1. For each class in the contract, write its full public signature (methods, args, return shape) and the file it lives in.
2. Draw the load/dependency graph (entry → configuration/current/errors → railtie → scoped/relation_extension → models → controller → policy → generators).
3. Restate the 6 security invariants and, for each, name the phase + spec that proves it.
4. Specify the Combustion fixture schema the harness (Phase 01) must create: `tenants(slug)`, `users`, `memberships(user_id,tenant_id,role)`, and a scoped `widgets(tenant_id,name)` table for engine tests.
5. Record any deviation from `PLAN.md` with rationale — but the public surface stays frozen.

## Acceptance
- `DESIGN.md` exists and covers **every** symbol in the PLAN contract with matching names.
- No file under `lib/` changed.

## On completion
Write a scratchpad summary: the symbol inventory and the fixture schema.
