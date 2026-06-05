# TenancyDable v0.3.0 — Action Cable + Job-caveat Plan (frozen)

> **Authoritative for this run.** The gem exists and is green at **v0.2.0** on this
> branch (`feat/v0.3.0-action-cable`, stacked on `nits/v0.2.0`). Honor the original
> frozen contract in [`.midgal/PLAN.md`](PLAN.md) + [`DESIGN.md`](../DESIGN.md)
> EXCEPT where amended here. Keep the suite green at every phase. Lean 6-phase run.
> All work commits on THIS branch — never `master`.

## Scope (and explicit non-scope)

This run makes the gem first-class with **Action Cable** and closes the one
**gem-side ActiveJob caveat**. Two additive features → version bump to **0.3.0**.

**IN scope (gem only):**
1. **Action Cable** — a `TenancyDable::Channel` concern that resolves the tenant per
   subscription, enforces membership, and runs channel actions inside the tenant
   context — the Cable parallel to `Controller::Resolvable`.
2. **ActiveJob membership** — `TenancyDable::Job` currently propagates the tenant but
   NOT the membership (`current_membership` is nil in `perform`). Carry the membership
   too, so a job's context matches a request's.

**OUT of scope — do NOT touch (guardrails):**
- **Any skeleton adaptation.** This run changes ONLY the `tenancy_dable` gem. Do not
  edit, reference, or migrate the host skeleton app (`ror_saas_multitenant_test`),
  its `Current`, `Agents::RunJob`, or its `TenantChannel`. That is deferred host work.
- **The gem does NOT own Cable authentication.** Connection-level user identification
  stays the host's job (`identified_by :current_user`, however the host authenticates
  — cookie/session/etc.). Do NOT add cookie/session parsing to the gem. The Channel
  concern READS `current_user` from the connection; it does not establish it. Document
  the one-line host requirement; do not ship a `Connection` auth concern.
- **Inherent, documented Job seams stay as-is** (they are correct, not caveats to
  "fix"): tenant captured at *enqueue* time; a *deleted* tenant restores
  `with_tenant(nil)` (fail-open, or fail-closed under `require_tenant`). Keep both;
  just extend them to carry membership symmetrically.

## Frozen additions

### A. `TenancyDable::Channel` (opt-in) — `lib/tenancy_dable/channel.rb`
Opt-in like `Job`: NOT auto-required (`require "tenancy_dable/channel"`); Action Cable
stays an optional dependency (the host has it via `rails`). The including class is an
`ActionCable::Channel::Base`. The connection must `identified_by :current_user`.

Public surface (FROZEN names):
- `current_tenant` — memoized `config.tenant_class.find_by(config.slug-ish)`: looks the
  tenant up by **slug** from `params[config.slug_param]` (subscription params). Slug-only
  (invariant 5), never an id. Returns nil if absent/unknown.
- `current_membership` — memoized `current_user&.membership_for(current_tenant)`.
- `tenant_member?` — `current_membership.present?`.
- `reject_unless_member!` — call in `#subscribed`; `reject` unless `tenant_member?`
  (the Cable parallel to `Resolvable`'s membership enforcement).
- `stream_for_tenant(suffix = nil)` — `stream_from "tenant:#{current_tenant.id}"`
  (+ `":#{suffix}"` when given). Tenant-namespaced stream naming (no cross-tenant stream).
- **Automatic context:** every incoming channel action runs inside
  `TenancyDable.with_tenant(current_tenant)` with `current_membership` also set — wrap
  `perform_action` (call `super` inside the block) so action handlers are tenant-scoped
  exactly like controller actions. A `with_tenant_context(&blk)` instance helper is
  provided for use inside `#subscribed` (where DB reads also need scoping).
- All helpers are **safe when no tenant resolves** (nil tenant ⇒ `reject_unless_member!`
  rejects; `with_tenant`-wrapping with nil ⇒ unscoped/fail-open per config).

### B. `TenancyDable::Job` carries membership — `lib/tenancy_dable/job.rb`
- `serialize` adds `SERIALIZED_MEMBERSHIP_KEY` (`"tenancy_dable_membership_id"`) =
  `TenancyDable.current_membership&.id` alongside the existing tenant id.
- `deserialize` reads it; `around_perform` reloads it via `config.membership_class
  .find_by(id:)` and sets `TenancyDable.current_membership` for the duration of `perform`
  (inside the existing `with_tenant` block, so the `ensure` restores it — no leak).
- Backward compatible: a payload without the membership key (older enqueues) restores
  nil membership; tenant propagation is unchanged.

## Versioning & contract impact
- Bump `TenancyDable::VERSION` `0.2.0` → **`0.3.0`** (additive: new opt-in concern +
  additive job field).
- `spec/contract_spec.rb`: add `TenancyDable::Channel` (responds to the frozen helpers)
  to the locked surface; error count still 8; settings count unchanged (no new config).
- `DESIGN.md`: new §for the Channel concern + the Job membership field.
- Action Cable is an OPTIONAL dep (opt-in require), like ActiveJob — no gemspec runtime
  change; `rails` (dev dep) already provides `actioncable` for the harness.

## Phase index
| # | Phase | Spec | Validates |
|---|---|---|---|
| 00 | Contract delta → DESIGN.md | `v03/00-contract-delta.md` | DESIGN has `TenancyDable::Channel`; suite green |
| 01 | Job carries membership | `v03/01-job-membership.md` | `rspec spec/integration` |
| 02 | `TenancyDable::Channel` concern | `v03/02-channel-concern.md` | `standardrb` |
| 03 | Cable harness + channel specs | `v03/03-channel-specs.md` | `rspec spec/channels` |
| 04 | Docs + version 0.3.0 | `v03/04-docs-version.md` | grep + `rspec` |
| 05 | Critic / verify | `v03/05-critic.md` | `bundle exec rake` |
