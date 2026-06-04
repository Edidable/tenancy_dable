# Phase 05 — Slug Resolution (controller concern)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 04 (identity, esp. `membership_for`) exists.

## Files
- `lib/tenancy_dable/controller/resolvable.rb` — `TenancyDable::Controller::Resolvable`:
  - class macro `resolve_tenant!(**before_action_opts)` installs a `before_action`.
  - resolution: `tenant_model.find_by!(slug: params[config.slug_param])` (honor `on_tenant_not_found` → RecordNotFound or null), resolve acting user via `config.current_user_resolver`, require `user.membership_for(tenant)` else raise `NotAMemberError`, set `TenancyDable.current_tenant` + `current_membership`.
  - `default_url_options` merges `{ config.slug_param => TenancyDable.current_tenant&.slug }`.
  - **slug only** — never read a tenant id from the URL.
- Add a `WidgetsController` + `/:tenant_slug/widgets` route to the Combustion app to exercise it (used by Phase 10).

## Acceptance
- Valid slug + member sets current tenant/membership.
- Unknown slug honors `on_tenant_not_found`.
- Authenticated non-member raises `NotAMemberError`.

## Validation
`bundle exec standardrb`.

## On completion
Scratchpad: the resolution order + the auth-agnostic `current_user_resolver` seam.
