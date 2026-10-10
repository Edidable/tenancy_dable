# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
For what counts as a breaking vs. additive change, and how to bump the gem across
derived edidable projects, see [UPGRADING.md](UPGRADING.md).

## [Unreleased]

_Nothing yet._

## [0.5.0] - 2026-10-10

See [UPGRADING.md](UPGRADING.md#upgrading-to-v050).

Three changes are **on by default and can raise in a host that works today**: the read
guard, the refusal to write into another tenant (create, update, destroy, `touch`,
`delete`, `update_columns`, `insert_all`, `upsert_all`), and the fiber isolation check.
A `TenancyDable::Job` whose tenant vanished before it ran also raises
`TenantNotFoundError` now, instead of running with no tenant. Each
refuses a cross-tenant leak that 0.4.0 let through, and each has an escape hatch
(`guard_reads = false`, `isolation_check = :warn`/`:off`, or a local
`with_tenant(other) { ... }` / `without_tenant { ... }`). Everything else is additive.
Error classes go from **8 to 12** and config settings from **14 to 19**. Because this is
a `0.MINOR` bump, `~> 0.4.0` pins will **not** pick it up automatically (review by hand,
see [UPGRADING.md](UPGRADING.md#pre-10-caveat)). The contract is
[DESIGN.md §16](DESIGN.md).

### Security

- **The read guard closes invariant 2 on the read side.** While acting in tenant B, a
  read through a tenant's own association (`a.widgets.to_a`, `.find`, `.count`,
  `.pluck`, `.exists?`, `a.widget_ids`, `a.widgets.ids`, `.load_async`, a `has_one`)
  returned tenant A's rows, because an association scope replaces the default scope's
  tenant predicate instead of adding to it. So did `rewhere(tenant_id: a.id)`, `merge`
  with an unscoped relation, `unscope(where: :tenant_id)` (every tenant's rows) and an
  `or` with another tenant's relation. Such a read now raises
  `TenancyDable::CrossTenantReadError`. Setting `guard_reads = false` restores the
  0.4.0 behaviour.
- **`a.widgets.destroy_all` no longer deletes another tenant's rows.** Acting as B, it
  loaded and destroyed tenant A's records without reaching the bulk-write guard. Loading
  the target is refused now, and nothing is deleted.
- **Creating into another tenant is refused.** Inside `with_tenant(b)`,
  `a.widgets.create!`, `Widget.create!(tenant: a)`, `Widget.create!(tenant_id: a.id)`
  and `save(validate: false)` with another tenant's id persisted a row in tenant A. They
  now raise `TenancyDable::CrossTenantWriteError`, with or without validators.
- **The read guard also refuses** `invert_where`, `where.not`, ranges and subqueries on
  the tenant column (also through `merge` and `unscoped`), table-keyed
  `unscope(where: {widgets: :tenant_id})`, a relation built with no tenant (or inside
  `without_tenant`) and loaded inside a tenant, `cache_key`/`cache_version` of a
  refused relation, and a refused relation used as a subquery. `to_sql` and `arel`
  on a refused relation raise.
- **Writing to another tenant's record is refused.** Updating, destroying, touching,
  `update_columns` and `delete` of a record of another tenant, and `valid?` on it,
  raise `CrossTenantWriteError` (0.4.0 persisted the change, or failed only in a
  validator). `insert_all`, `upsert_all` and their relatives raise when a row names
  another tenant, and an upsert raises when its conflict target does not include
  the tenant column (the primary key, or any upsert on an adapter without conflict
  targets).
- **`update_all(tenant_id: ...)` and `update_columns(tenant_id: ...)` raise
  `TenantImmutableError`.**
- The guard targets the shapes Active Record produces on its own. Explicit relation
  surgery stays possible and is documented as a residual: `Model.unscoped` with no
  tenant predicate, `except(:where)`, `only`, an `or` with an unscoped or a stale relation,
  SQL-string predicates, raw SQL strings, `reload` by id and the cache key of an already
  loaded association (see the README).

### Added

- **Declared tenancy and an audit.** `tenant_global because: "..."` (optional `tag:`,
  `allow_tenant_fk:`) is available on every Active Record class, `belongs_to_tenant`
  accepts `tag:`, and a second declaration on a lineage raises `ConfigurationError`.
  `TenancyDable.audit` returns findings for models that declare nothing
  (`:undeclared`), are declared global but carry the tenant column
  (`:global_with_tenant_fk`), or are scoped with no index leading with the tenant
  column (`:scoped_without_index`). `rake tenancy_dable:audit` prints them and exits 1.
  `TenantModel`, `UserModel` and `MembershipModel` declare themselves. New settings
  `audit_allowed` and `audit_ignored_namespaces`.
- **Fiber safety.** Every write of tenant state checks that Active Support's isolation
  level suits the running fiber scheduler, and raises `UnsafeIsolationError` otherwise
  (`isolation_check`: `:raise` default, `:warn`, `:off`). `TenancyDable.snapshot`,
  `Snapshot#restore` and `TenancyDable.carry` hand the tenant, the membership and the
  bypass flag to another thread or fiber.
- **An audited `without_tenant`.** `without_tenant(reason: nil)` publishes a
  `"without_tenant.tenancy_dable"` event (`reason`, `tenant_id`, `call_site`) when
  something subscribes; `require_bypass_reason = true` makes a blank reason raise
  `BypassReasonError`.
- **Locales.** The gem ships `en` and `pt-BR` translations for its three validation
  messages (`cross_tenant`, `last_owner`, `slug_format`); a host's own locale files
  override them.
- **Settings:** `guard_reads`, `isolation_check`, `require_bypass_reason`,
  `audit_allowed`, `audit_ignored_namespaces`. **Errors:** `CrossTenantReadError`,
  `CrossTenantWriteError`, `UnsafeIsolationError`, `BypassReasonError`.

### Changed

- **Validation messages are I18n keys.** The cross-tenant `belongs_to` error, the
  last-owner error and the slug-format error resolve through `errors.messages.*`. In
  `en` the text is unchanged and `errors[:attribute]` reads the same. `errors.details`
  now carries the symbols `:cross_tenant` and `:last_owner` instead of an English
  String. A host in another locale translates the three keys or enables fallbacks that reach `:en`.
- **Reads and creates that used to be safe-but-empty now raise.** `Widget.where(tenant_id:
  other)` and `IN` lists across tenants, a preload of another tenant's owners, and
  creating a record with another tenant's id used to return nothing, the current
  tenant's rows, or (for creates) write into the other tenant. Fix the call site with
  `with_tenant(other) { ... }`, or `without_tenant(reason: "...") { ... }` when the
  crossing is deliberate.
- **Locale loading.** A host's own locale files now override the gem's for the same
  key. `en` always loads; `pt-BR` loads only when the host declares it in
  `config.i18n.default_locale` or `config.i18n.available_locales` in
  `config/application.rb`, so an English-only host's `I18n.available_locales` does
  not gain `pt-BR`. A `pt-BR` host now sees Portuguese where 0.4.0 showed literal
  English. Fallbacks must reach `:en` (`config.i18n.fallbacks = [:en]`).
- **`TenancyDable::Job`** raises `TenancyDable::TenantNotFoundError` when the tenant
  it was enqueued in no longer exists, instead of running under no tenant.
- **`without_tenant(reason:)`** accepts only `nil`, a String or a Symbol (anything
  else raises `BypassReasonError`); `call_site` is an absolute path.
- **The audit** reports a global model that shares a scoped model's table as
  `:global_with_tenant_fk` even with `allow_tenant_fk: true`, and skips only real STI
  subclasses.
- **Fiber docs.** With `require_tenant` off, a thread or fiber that lost the context
  reads every tenant (the fail-open default): set `require_tenant = true` and use
  `carry`. The isolation check also fires for host code that opens an `Async`/`Sync`
  reactor under thread isolation. Write tenant state only through the facade.
- **New class methods on every Active Record class** (`tenant_global`,
  `tenancy_declaration`, `tenancy_global_reason`, `tenancy_tag`) can collide with a
  host macro of the same name on `ApplicationRecord`.

## [0.4.0] - 2026-09-28

See [UPGRADING.md](UPGRADING.md#behavior-differences-to-expect).

### Security

- **`current_membership` no longer returns a membership of another tenant.** Inside
  `with_tenant(other_tenant)`, or after `current_tenant=` moved to another tenant, it
  kept returning the outer tenant's membership, so a `pundit_context` built from it
  decided with that tenant's role. It now returns nil there, and the membership reads
  again once `with_tenant` restores the outer tenant. A host that treats "no
  membership" as a system context now sees nil for a member of another tenant too,
  and must also check `foreign_membership?`.

### Added

- **`TenancyDable.foreign_membership?`**: true when a membership is set but is not the
  current tenant's, including when no tenant is current. `TenancyDable::Job` keeps
  serializing the stored membership, so job payloads are unchanged.

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

[Unreleased]: https://github.com/edidable/tenancy_dable/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/edidable/tenancy_dable/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/edidable/tenancy_dable/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/edidable/tenancy_dable/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/edidable/tenancy_dable/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/edidable/tenancy_dable/releases/tag/v0.1.0
