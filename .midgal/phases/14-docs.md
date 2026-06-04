# Phase 14 — Documentation

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 13 is green (document the real, working API).

## Files
- `README.md` — finalize: install, `tenancy_dable:install`, full configuration reference, the four layers with short code samples, and the comparison vs `acts_as_tenant`/`rails-tenantify` (we add memberships/roles/slug/authorization on top of a self-contained engine).
- `UPGRADING.md` — **the propagation story**: how a derived edidable project consumes the gem, the semver policy, how to bump across projects (`bundle update tenancy_dable`), and a migration guide from the skeleton's in-house `Tenantable`/`SetCurrentTenant`/`ApplicationPolicy` to the gem (what to delete, what to include, what stays).
- `CHANGELOG.md` — move skeleton items under a dated `0.1.0` heading.
- Cross-link `DESIGN.md`.

## Acceptance
- README examples match the real public API (no aspirational drift).
- UPGRADING covers both "new project" and "migrate existing skeleton app".

## Validation
Docs present and internally consistent (no references to removed/renamed symbols).

## On completion
Scratchpad: doc map + the migration checklist.
