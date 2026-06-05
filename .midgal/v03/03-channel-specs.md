# v0.3 Phase 03 — Cable test harness + channel specs

**Read `.midgal/V03_PLAN.md` + the phase-02 scratchpad.** Verify `lib/tenancy_dable/channel.rb` exists.

## Tasks
1. **Harness:** add Action Cable to the Combustion app under `spec/internal/`:
   - `app/channels/application_cable/connection.rb` (`identified_by :current_user`; a minimal `connect` that trusts a test-provided identifier — this is harness-only, not gem code).
   - `app/channels/application_cable/channel.rb`.
   - a fixture `TenantChannel < ApplicationCable::Channel` that `include TenancyDable::Channel`, calls `reject_unless_member!` + `stream_for_tenant` in `#subscribed`, and defines one action that reads tenant-scoped data (e.g. `Widget.count`) to prove scoping.
   - ensure `actioncable` is loaded in `spec/rails_helper.rb` and `type: :channel` specs work (rspec-rails); `require "tenancy_dable/channel"`.
2. **Specs** `spec/channels/*_spec.rb` (type: :channel, `stub_connection(current_user: …)`):
   - a member of the tenant subscribes successfully and gets `have_stream_from "tenant:#{tenant.id}"`.
   - a non-member is **rejected** (`subscription.rejected?`).
   - an unknown/absent slug ⇒ rejected (no tenant ⇒ not a member).
   - inside a channel **action**, `TenancyDable.current_tenant` is set and a scoped read returns ONLY the acting tenant's rows (cross-tenant rows invisible) — proving the `perform_action` wrap.
   - context does not leak after the action (CurrentAttributes reset).

## Acceptance / Validation
- `bundle exec rspec spec/channels` green.

## On completion
Scratchpad: harness files added + the isolation proof inside a channel action.
