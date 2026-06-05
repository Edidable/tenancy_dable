# v0.3 Phase 02 — `TenancyDable::Channel` concern

**Read `.midgal/V03_PLAN.md` (§A) + the phase-00 scratchpad.** Library code only; specs come in phase 03. Respect the guardrail: the gem does NOT own Cable auth — read `current_user` from the connection, never parse cookies/sessions.

## File
`lib/tenancy_dable/channel.rb` — `module TenancyDable::Channel` (`extend ActiveSupport::Concern`), opt-in (NOT required by the entry point; the host does `require "tenancy_dable/channel"`). Frozen public surface:
- `current_tenant` — memoized; `config.tenant_class.find_by(slug: params[config.slug_param])`. **Slug only** (invariant 5). nil if absent/unknown.
- `current_membership` — memoized; `current_user&.membership_for(current_tenant)`.
- `tenant_member?` — `current_membership.present?`.
- `reject_unless_member!` — `reject unless tenant_member?` (host calls it in `#subscribed`).
- `stream_for_tenant(suffix = nil)` — `stream_from "tenant:#{current_tenant.id}"` (append `":#{suffix}"` if given). Never a non-tenant-namespaced stream.
- `with_tenant_context(&block)` — `TenancyDable.with_tenant(current_tenant) { TenancyDable.current_membership = current_membership; block.call }` (tenant + membership for the block).
- **Auto-scope actions:** override `perform_action(data)` to call `super` inside `with_tenant_context` so every received-message handler runs tenant-scoped. (Use `super` so framework dispatch is unchanged.)

Notes:
- Reference `current_user` (provided by the connection's `identified_by :current_user`); do not assume any auth stack.
- Reference Action Cable constants lazily so merely loading the gem without Action Cable never errors (the file is only required by hosts that use Cable).
- Standard-clean.

## Acceptance / Validation
- `bundle exec standardrb lib`
- File loads in the harness (a require smoke is fine); full channel specs land in phase 03.

## On completion
Scratchpad: the final helper list + how `perform_action` wrapping is implemented.
