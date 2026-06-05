# TenancyDable — Final Report

**Phase 15 (Critic / Hardening), the final adversarial gate.**
Version `0.1.0` · `bundle exec rake` green · audited 2026-06-04.

This report is the close-out of the 16-phase autonomous build of `tenancy_dable`,
the multi-workspace tenancy gem for the **edidable** Rails SaaS skeleton family.
It records what shipped, proves the six security invariants from
[`.midgal/PLAN.md`](.midgal/PLAN.md), confirms zero API-vs-contract drift, and
lists the deferred seams a host should know about. The frozen per-symbol contract
is in [DESIGN.md](DESIGN.md); usage is in [README.md](README.md).

---

## Verdict — PASS

| Gate | Result |
|---|---|
| `bundle exec rake` (rspec + Standard) | **exit 0** |
| RSpec | **251 examples, 0 failures** — order-independent (10 seeds verified) |
| Standard (lint) | **0 offenses** |
| API vs. frozen contract | **no drift** — locked by `spec/contract_spec.rb` (60 examples) |
| Security invariants (6) | **6/6 proven** (existing specs + new red-team suite) |
| `TenancyDable::VERSION` | **`0.1.0`** (matches CHANGELOG `[0.1.0]` + the `~> 0.1.0` pin in docs) |

---

## 1. Security invariant audit

The six invariants from `PLAN.md §Security invariants`, each with its primary
proving spec **and** the adversarial attack added this phase in
[`spec/security/red_team_spec.rb`](spec/security/red_team_spec.rb) (which plays
attacker and asserts the breach is refused).

| # | Invariant | Status | Primary proof | Red-team attack (new) |
|---|---|---|---|---|
| 1 | **Fail-closed when configured** — `require_tenant` active + no tenant ⇒ **raises** `NoTenantError`, never a silent `all` | ✅ PASS | `spec/scoping/default_scope_spec.rb` | raises at **every** read entry point (`all`/`count`/`first`/`last`/`pluck`/`exists?`/`find_by`/`where`), leaking no rows |
| 2 | **No cross-tenant read path** (direct query · association · bulk write) | ✅ PASS | `spec/scoping/{default_scope,cross_tenant,bulk_write_guard}_spec.rb`, `spec/integration/cross_tenant_isolation_spec.rb` | 3-way attack as tenant A: `find`/`where(id:)`/`where(tenant_id: B)` all empty; cross-tenant `belongs_to` invalid; bulk write refused **even via `unscoped`** |
| 3 | **`tenant_id` immutable after create** ⇒ `TenantImmutableError` | ✅ PASS | `spec/scoping/tenant_assignment_spec.rb` | refuses **all three** write paths (fk writer, association writer, `update!` mass-assign); row never moves |
| 4 | **Pundit scope fails closed** — `scope.none` with no active tenant | ✅ PASS | `spec/policy/scope_spec.rb` | `.none` **poisons the chain** — `to_a`/`count`/`exists?`/re-`where(id:)` all stay empty |
| 5 | **Slug-only resolution** — never trust a tenant id from the URL | ✅ PASS | `spec/resolution/slug_only_spec.rb` | id-in-slug-slot resolves to `nil` through the exact `find_by(slug:)` path Resolvable uses |
| 6 | **No PII/secret leakage** — audit logs carry tenant ids only | ✅ PASS | *(was unproven — gap CLOSED here)* | with a logger spy: the `:log` override line and the `:raise` error message contain **only `#<id>`**, never the tenants' names/slugs |

### Invariant 6 — log audit detail

A `grep` of the entire `lib/` tree found **exactly one** logging call —
`lib/tenancy_dable.rb:132`, the `audit_overrides: :log` path — and it interpolates
`previous.id` and `new_tenant.id` only. Every `raise` message across the gem
(`TenantOverrideError`, `ConfigurationError`, the scoping/bulk-write errors)
carries ids, class names, role names, or setting names only — no record payloads.
The one slug that appears in a message (`NotAMemberError`) is a public URL
identifier already present in the request path, not PII. DESIGN §11 had noted "no
dedicated unit spec" for invariant 6; that gap is now closed by two executable
examples in the red-team suite.

---

## 2. API vs. frozen contract — no drift

A runtime introspection pass verified every contract item from `PLAN.md` — all
pass, zero drift. It is now a **permanent contract-lock spec**
([`spec/contract_spec.rb`](spec/contract_spec.rb), 60 examples) so any future
change that drifts from the frozen surface fails CI here loudly, instead of
silently breaking a downstream edidable project. What it locks:

- **File layout** — all 16 contract files present.
- **Configuration** — all 13 settings exist with their **exact frozen defaults**
  (`tenant_model: "Tenant"`, `roles: %w[owner admin member]`, `require_tenant: false`,
  `audit_overrides: :log`, … ; `rls_statement`/`current_user_resolver` callable).
- **Facade** — `configure`, `configuration`, `reset_configuration!`, the
  `current_tenant`/`current_membership` accessors, `with_tenant`, `without_tenant`,
  `pundit_context(user:, tenant:, membership:)` (keyword signature verified).
- **`Current`** — `< ActiveSupport::CurrentAttributes`; attributes `tenant`,
  `membership`, `tenant_scope_disabled`.
- **`Scoped`** — `belongs_to_tenant(name = :tenant, **opts)` and
  `validates_uniqueness_to_tenant(*fields, **opts)` (signatures verified).
- **`RelationExtension`** — `update_all`/`delete_all`/`destroy_all`.
- **Identity** — `TenantModel#owners`, `MembershipModel#manager?`,
  `UserModel#membership_for`/`#member_of?`.
- **`Resolvable`** — `resolve_tenant!(**opts)`, `default_url_options`.
- **Authorization** — `Policy::Context` is a `Data` of `[user, tenant, membership]`
  with `#role`; `Policy::Base` has the secure-by-default seven (all 5 frozen
  actions return `false`) and `Base::Scope#resolve`.
- **Errors** — all 8 subclasses of `TenancyDable::Error < StandardError`.
- **Generators** — `TenancyDable::Generators::InstallGenerator` (`tenancy_dable:install`)
  and `ModelGenerator` (`tenancy_dable:model`).
- **Seam** — `TenancyDable::Job` concern present (additive, DESIGN §10-I).

---

## 3. What shipped

A self-contained tenancy engine (no `acts_as_tenant`/`rails-tenantify` dependency)
in four layers plus seams:

1. **Configuration & context** — validated `Configuration` + the `TenancyDable`
   facade over `Current` (`ActiveSupport::CurrentAttributes`); `current_tenant=`
   is the single audited mutation path (audit-override policy + optional RLS hook).
2. **Row-scoping engine** — `Scoped`/`belongs_to_tenant`: fail-closed default scope,
   create-time fk auto-assignment, fk immutability, cross-tenant `belongs_to`
   validation, `validates_uniqueness_to_tenant`; `RelationExtension` bulk-write guard.
3. **Identity** — `TenantModel` (slug generation + graph + `#owners`),
   `MembershipModel` (config-derived role predicates, last-owner guard, `#manager?`;
   deliberately **not** tenant-scoped), `UserModel` (`#membership_for`/`#member_of?`).
4. **Resolution & authorization** — `Controller::Resolvable` (`resolve_tenant!`,
   slug-only, membership-enforcing, `default_url_options` injection);
   `Policy::Context` + secure-by-default `Policy::Base` + fail-closed `Scope`.

Plus: **opt-in** `TenancyDable::Job` (ActiveJob tenant propagation), the
`tenancy_dable:install` / `tenancy_dable:model` generators, the 8-error hierarchy,
a Combustion + sqlite3 + RSpec harness exercising real ActiveRecord/ActionPack,
and the docs (README, UPGRADING, DESIGN, CHANGELOG).

---

## 4. Coverage summary

**251 examples, 0 failures**, proven order-independent (10 seeds verified green:
1, 2, 7, 8, 42, 777, 12345, 31337, 54321, 99999 — the fix in §5).

| Suite | Files | Examples | Covers |
|---|---:|---:|---|
| `spec/scoping` | 6 | 28 | default scope, immutability, cross-tenant, bulk guard, uniqueness, RLS |
| `spec/identity` | 6 | 48 | tenant/user/membership graph, roles, last-owner guard, not-scoped |
| `spec/resolution` | 5 | 17 | slug-only, membership enforcement, not-found, url options |
| `spec/policy` | 6 | 43 | secure-by-default, capability matrix, context, same-tenant, scope |
| `spec/generators` | 2 | 17 | install (idempotent) + model generators |
| `spec/integration` | 5 | 20 | end-to-end isolation, bulk flow, resolution+policy, RLS, ActiveJob |
| `spec/security` | 1 | 9 | **adversarial red-team (this phase)** — all 6 invariants |
| `spec/contract_spec.rb` | 1 | 60 | **contract lock (this phase)** — frozen surface + signatures |
| root (`tenancy_dable`, `schema`) | 2 | 9 | facade smoke + fixture schema shape |
| **Total** | **34** | **251** | |

---

## 5. Phase 15 hardening changes

1. **Fixed an order-dependent test flake** (genuine harness hardening). Root cause:
   `Membership`'s role predicates (`owner?`/`admin?`/`member?`) are baked at
   `include`-time from `config.roles` (a documented design choice — DESIGN §6.2),
   but the host model was **lazily autoloaded**; when a config-mutating spec was
   the first to reference `Membership`, the wrong predicate set baked in and stayed
   wrong (deterministic repro:
   `rspec spec/policy/capability_matrix_spec.rb:60 spec/identity/membership_roles_spec.rb --order defined`).
   Fix: `config.eager_load = true` in `spec/rails_helper.rb`, so all host models
   load **once, up front, against the default config** — mirroring the real-world
   contract (a host's initializer sets roles before models load). Suite is now
   order-independent.
2. **Added `spec/security/red_team_spec.rb`** — 9 adversarial examples that attack
   tenant isolation across all six invariants (closing the invariant-6 proof gap).
3. **Added `spec/contract_spec.rb`** — 60 examples locking the frozen public
   surface (every symbol, frozen default, and documented signature) so future
   contract drift fails CI loudly rather than silently breaking a downstream app.
4. **Bumped `TenancyDable::VERSION`** `0.0.1` → `0.1.0`, aligning code with the
   dated `CHANGELOG [0.1.0]` and the `~> 0.1.0` pin documented in README/UPGRADING;
   updated the CHANGELOG test-harness note.

---

## 6. Deferred seams & known behaviors

These are **intentional**, contract-consistent decisions — recorded so a
security-conscious host can make an informed call. None is a defect.

- **Fail-OPEN is the default.** `require_tenant` ships `false`, so an unscoped
  query on a scoped model with no current tenant returns `all` rather than raising.
  The web path is always scoped (resolution sets the tenant), so this is the
  backstop posture for jobs/console/rake. Hosts wanting fail-closed everywhere set
  `config.require_tenant = true` (or a callable). Documented in README §security.
- **`Job` deleted-tenant → fail-open.** `TenancyDable::Job` restores the
  enqueue-time tenant by id; if that tenant was **deleted** before `perform`, it
  restores `with_tenant(nil)` and the job runs unscoped (mirroring the default
  scope). This composes correctly with the above: a host running `require_tenant`
  truthy gets a job that **fails closed** (raises `NoTenantError`) instead of
  silently running unscoped. Whether a deleted tenant should hard-fail regardless
  of `require_tenant` is left to the host. `Job` is **opt-in** (not auto-required),
  so ActiveJob stays an optional dependency (DESIGN §10-I).
- **`TenantNotFoundError` coexists with `ActiveRecord::RecordNotFound`.** The
  `Resolvable` `:raise` path resolves via `find_by!`, which raises
  `RecordNotFound`; `TenantNotFoundError` is part of the frozen 8-error hierarchy,
  reserved for hosts and non-bang `find_by` strategies (DESIGN §10-A). Both ship.
- **Role predicates are bound at `include`-time** (DESIGN §6.2). This is by design
  (the conventional, introspectable `respond_to?(:owner?)` surface) and is correct
  in production, where the initializer configures roles before models load. The
  test harness now reproduces that ordering via eager-load (§5.1). A host that
  reconfigures `roles` at runtime after boot must reload its identity models.
- **Bulk-write guard pins on equality.** The guard admits a bulk write only when
  the relation has an equality predicate `tenant_fk = current_tenant.id`
  (`where_values_hash`). A relation scoped to the tenant by a non-equality
  predicate (e.g. a raw SQL `WHERE`) is conservatively **refused** — wrap such a
  write in `TenancyDable.without_tenant` to opt out explicitly. Fail-safe by intent.

---

## 7. Outstanding

Nothing blocking. The whole phased build remains **uncommitted on `master`** (no
phase spec instructed a commit); committing/tagging `v0.1.0` and publishing is a
release-time action for the maintainer, outside the autonomous build's scope.
