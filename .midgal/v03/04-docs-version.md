# v0.3 Phase 04 — Docs + version bump 0.3.0

**Read `.midgal/V03_PLAN.md`.** Document the two features against the now-real code and bump the version. Verify phases 01–03 landed.

## Files
- `lib/tenancy_dable/version.rb`: `VERSION = "0.3.0"`.
- `spec/contract_spec.rb`: add `TenancyDable::Channel` to the locked surface (a module that, when included in an `ActionCable::Channel`, responds to `current_tenant`, `current_membership`, `tenant_member?`, `reject_unless_member!`, `stream_for_tenant`, `with_tenant_context`). Keep error count 8, settings count unchanged.
- `README.md`: new "Action Cable" subsection — opt-in `require "tenancy_dable/channel"`, the `identified_by :current_user` connection requirement, a `TenantChannel` example (`reject_unless_member!` + `stream_for_tenant`, auto-scoped actions). Also note `TenancyDable::Job` now restores `current_membership`.
- `UPGRADING.md`: short "Action Cable" note (how a host adopts the Channel concern; the gem does not own connection auth) + the Job-membership behavior change.
- `CHANGELOG.md`: dated `## [0.3.0]` — Action Cable `Channel` concern; Job carries membership; link refs.
- `FINAL_REPORT.md`: append a "v0.3.0 addendum" (Action Cable + Job membership, new spec count).

## Acceptance / Validation
- `grep -q "0.3.0" lib/tenancy_dable/version.rb CHANGELOG.md`
- `grep -q "tenancy_dable/channel" README.md`
- `bundle exec rspec` green (update any version-pinning spec if present).

## On completion
Scratchpad: doc deltas + confirm 0.3.0 everywhere.
