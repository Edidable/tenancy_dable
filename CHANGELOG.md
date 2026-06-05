# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
For what counts as a breaking vs. additive change, and how to bump the gem across
derived edidable projects, see [UPGRADING.md](UPGRADING.md).

## [Unreleased]

_Nothing yet._

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

[Unreleased]: https://github.com/edidable/tenancy_dable/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/edidable/tenancy_dable/releases/tag/v0.1.0
