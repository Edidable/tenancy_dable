# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
For what counts as a breaking vs. additive change, and how to bump the gem across
derived edidable projects, see [UPGRADING.md](UPGRADING.md).

## [Unreleased]

_Nothing yet._

## [0.3.0] - 2026-06-05

Two **additive** features that make the gem first-class with Action Cable and close
the one gem-side ActiveJob caveat. Default behavior is unchanged, so no host breaks;
the frozen public surface holds except as recorded in [DESIGN.md §14](DESIGN.md#14-v030-delta--action-cable--job-membership-additive--frozen-for-this-run).
Error hierarchy stays at **8 classes** and config settings stay at **14** (the
Channel concern reuses `slug_param` and adds no setting). Because this is a
`0.MINOR` bump, `~> 0.2.0` pins will **not** pick it up automatically (review by
hand — see [UPGRADING.md](UPGRADING.md#pre-10-caveat)).

### Added

- **`TenancyDable::Channel`** — an opt-in Action Cable concern, the Cable parallel
  to `Controller::Resolvable`. Included into an `ActionCable::Channel::Base`
  subclass, it resolves the workspace **by slug** from the subscription params
  (invariant 5 — never an id), enforces membership (`reject_unless_member!` in
  `#subscribed`), streams from tenant-namespaced names (`stream_for_tenant` →
  `"tenant:<id>"`), and runs **every** channel action inside the tenant context by
  wrapping `perform_action` — so a channel's reads scope and its bulk writes pass
  the guard exactly like a controller action's. Frozen helpers: `current_tenant`,
  `current_membership`, `tenant_member?`, `reject_unless_member!`,
  `stream_for_tenant`, `with_tenant_context`. **Not auto-required** (Action Cable
  stays an optional dependency) — `require "tenancy_dable/channel"`. **The gem does
  not own Cable auth:** the host's `ApplicationCable::Connection` declares
  `identified_by :current_user`; the concern only *reads* it. No new config setting
  (resolution is fixed, reusing `slug_param`), no new error class.

### Changed

- **`TenancyDable::Job` carries the acting membership.** Alongside the enqueue-time
  tenant id, `Job` now serializes the membership id under a second namespaced key
  (`SERIALIZED_MEMBERSHIP_KEY = "tenancy_dable_membership_id"`) and restores
  `TenancyDable.current_membership` for the duration of `perform` — set **inside**
  the existing `with_tenant` block, so that block's `ensure` tears tenant **and**
  membership back down together (no leak across pooled jobs). A job's context (the
  workspace *and* the role within it) now matches the enqueuing request's, not just
  the tenant. **Backward compatible:** a payload enqueued before v0.3.0 has no
  membership key and restores a nil membership; tenant propagation is byte-for-byte
  unchanged. The `Job` concern's existing surface (`SERIALIZED_TENANT_KEY`,
  `tenancy_dable_tenant_id`, `serialize`/`deserialize`, `around_perform`) is
  untouched.

## [0.2.0] - 2026-06-05

Three small, **additive** fixes from the v0.1.0 review. Default behavior is
unchanged, so no host breaks; the public surface stays frozen except as recorded
in [DESIGN.md §13](DESIGN.md#13-v020-nits-delta-additive--frozen-for-the-nits-run).
Because this is a `0.MINOR` bump, `~> 0.1.0` pins will **not** pick it up
automatically (review by hand — see [UPGRADING.md](UPGRADING.md#pre-10-caveat)).

### Added

- **`config.on_not_a_member`** (Fix B) — host-selectable behavior when the acting
  user is authenticated but **not** a member of the resolved tenant. Default
  `:not_a_member_error` preserves v0.1.0 behavior (raise
  `TenancyDable::NotAMemberError`); `:not_authorized` raises
  `Pundit::NotAuthorizedError` instead (so controllers that already
  `rescue_from Pundit::NotAuthorizedError` need no bespoke clause); a callable
  `->(tenant)` runs via `instance_exec` in the controller for full control
  (redirect, `head :forbidden`, custom error). `Configuration#validate!` rejects an
  unknown symbol; a callable is accepted as-is. This is the **14th** config setting
  (was 13). Membership stays required in every mode — a non-member never gets a
  published tenant.
- **`CrossTenantError::MESSAGE`** (Fix C) — a `MESSAGE = "belongs to a different
  tenant"` constant, now the single source of truth for the cross-tenant
  `belongs_to` validation string. The previously-dead class (defined in the frozen
  8-error hierarchy but never referenced) is now the message's home. The validation
  still **adds** the error — it does not raise — and the string is byte-for-byte
  unchanged. Error hierarchy stays at **8 classes**.

### Changed

- **Generated `ApplicationPolicy` ships the `Context` alias** (Fix A) — the install
  generator's `application_policy.rb.tt` template now defines
  `Context = TenancyDable::Policy::Context` inside `ApplicationPolicy` (plus a
  commented `pundit_user` example), so a host's `ApplicationPolicy::Context.new(...)`
  resolves after adoption. Without it, the constant lives only in the enclosing
  `TenancyDable::Policy` module and existing host policy specs break on adoption.
  **Generated-template change only** — the gem ships no `ApplicationPolicy`, and no
  runtime lib symbol changes.

## [0.1.0] - 2026-06-04

First release: the full multi-workspace tenancy layer extracted from the edidable
Rails SaaS skeleton into one versioned gem. The frozen public contract is documented
in [DESIGN.md](DESIGN.md); usage is in [README.md](README.md).

### Added

- **Configuration & context.** `TenancyDable.configure { |c| … }` with a validated
  `Configuration` (raises `ConfigurationError` on bad config), and the
  `TenancyDable` facade for the current-tenant context: `current_tenant`,
  `current_membership`, `with_tenant`, `without_tenant`, `pundit_context`. State is
  held in `TenancyDable::Current` (`ActiveSupport::CurrentAttributes`), reset between
  requests and examples.
- **Row-scoping engine.** `TenancyDable::Scoped` with the `belongs_to_tenant` macro:
  a **fail-closed-when-configured** default scope (`require_tenant`), create-time
  `tenant_id` auto-assignment, `tenant_id` immutability after create, a cross-tenant
  `belongs_to` validation, and `validates_uniqueness_to_tenant`. A bulk-write guard
  (`TenancyDable::RelationExtension`, prepended to `ActiveRecord::Relation`) makes
  `update_all`/`delete_all`/`destroy_all` raise `BulkWriteError` unless pinned to the
  current tenant. Optional **Postgres RLS** hook (`config.rls` / `rls_statement`).
- **Identity model.** `TenancyDable::TenantModel` (memberships/users graph, slug
  generation + presence/uniqueness/format validation, `#owners`),
  `TenancyDable::MembershipModel` (role inclusion, role predicates generated from
  `config.roles`, `owners`/`admins` scopes, last-owner-demotion guard, `#manager?`),
  and `TenancyDable::UserModel` (`#membership_for`, `#member_of?`). `Membership` is
  deliberately **not** tenant-scoped (queried before a tenant is known).
- **Slug resolution.** `TenancyDable::Controller::Resolvable` with the
  `resolve_tenant!` macro: resolves the workspace **by slug only**, enforces
  membership (`NotAMemberError`), publishes `current_tenant`/`current_membership`,
  and injects the slug into `default_url_options`. Auth-agnostic via
  `current_user_resolver`.
- **Authorization.** `TenancyDable::Policy::Context` (user + tenant + membership
  `Data` type) and `TenancyDable::Policy::Base`: secure-by-default actions, private
  capability helpers (`same_tenant?`, `owner?`, `manager?`, `member?`), and a
  fail-closed `Scope`.
- **ActiveJob propagation (opt-in).** `TenancyDable::Job` carries the enqueue-time
  tenant through the serialized payload and restores it for `perform`. Not
  auto-required, so ActiveJob stays an optional dependency.
- **Generators.** `tenancy_dable:install` (idempotent: initializer, `tenants` +
  `memberships` migrations, `ApplicationPolicy`, `Current`, route scaffold) and
  `tenancy_dable:model NAME field:type` (a tenant-scoped model + migration).
- **Errors.** Eight-class hierarchy under `TenancyDable::Error`: `NoTenantError`,
  `TenantImmutableError`, `BulkWriteError`, `CrossTenantError`, `NotAMemberError`,
  `TenantNotFoundError`, `TenantOverrideError`, `ConfigurationError`.
- **Test harness & tooling.** Combustion + sqlite3 + RSpec harness under
  `spec/internal/` (real ActiveRecord + ActionPack, not mocks), Standard lint, the
  gemspec, MIT license, and the build plan in `.midgal/PLAN.md`. Includes an
  adversarial red-team suite (`spec/security/`) that asserts each of the six
  security invariants holds against direct attack; the audited results are in
  [FINAL_REPORT.md](FINAL_REPORT.md).
- **Documentation.** `README.md` (install, configuration reference, the four layers),
  `UPGRADING.md` (semver policy, cross-project bumps, and the skeleton → gem
  migration guide), and `DESIGN.md` (the frozen per-symbol contract).

[Unreleased]: https://github.com/edidable/tenancy_dable/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/edidable/tenancy_dable/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/edidable/tenancy_dable/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/edidable/tenancy_dable/releases/tag/v0.1.0
