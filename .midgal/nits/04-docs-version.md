# Nits Phase 04 — Docs + version bump 0.2.0

**Read `.midgal/NITS_PLAN.md`.** Document the three fixes against the now-real code and bump the version. Verify phases 01–03 landed.

## Files
- `lib/tenancy_dable/version.rb`: `VERSION = "0.2.0"`.
- `CHANGELOG.md`: add a dated `## [0.2.0]` section (move "Unreleased" items down) describing Fix A/B/C; add the compare/tag link refs.
- `README.md`:
  - add `on_not_a_member` to the full configuration reference table (default `:not_a_member_error`; the three forms).
  - in the authorization section, note the generated `ApplicationPolicy` ships `Context = TenancyDable::Policy::Context`.
- `UPGRADING.md` — **fold in the two gaps the v0.1.0 review flagged**:
  - in §3 (migrating an existing skeleton app): non-members → add `rescue_from TenancyDable::NotAMemberError` OR set `config.on_not_a_member = :not_authorized` to reuse an existing `Pundit::NotAuthorizedError` rescue; messages are English (localize in the rescue).
  - note that `ApplicationPolicy` should keep the `Context = TenancyDable::Policy::Context` alias (now generated) so existing policy specs using `ApplicationPolicy::Context.new(...)` keep working; build `pundit_user` with `TenancyDable.pundit_context(...)`.
- `FINAL_REPORT.md`: append a short "v0.2.0 addendum" summarizing the three fixes and the new total spec count.

## Acceptance / Validation
- `grep -q "0.2.0" lib/tenancy_dable/version.rb CHANGELOG.md`
- `grep -q "on_not_a_member" README.md UPGRADING.md`
- `bundle exec rspec` green (contract spec already updated in phase 02 for the version-independent surface; if any spec pins the version string, update it).

## On completion
Scratchpad: doc deltas + confirm version is 0.2.0 everywhere.
