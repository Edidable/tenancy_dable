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

---

## v0.2.0 addendum (nits run) — 2026-06-05

A lean 6-phase follow-up applied **three small, additive fixes** flagged by the
v0.1.0 review and bumped `TenancyDable::VERSION` `0.1.0` → **`0.2.0`** (additive
config setting = MINOR). Default behavior is unchanged — no host breaks — and the
frozen public surface holds except as recorded in [DESIGN.md §13](DESIGN.md). The
error hierarchy stays at **8 classes**; config settings go **13 → 14**; the six
security invariants (§1) hold as-is (no isolation default changed). Work landed on
branch `nits/v0.2.0`.

**Suite: `bundle exec rspec` green — 260 examples, 0 failures** (was 251 at v0.1.0;
**+9** from the nits specs):

| Fix | Change | New/changed spec | Δ examples |
|---|---|---|---:|
| **A** | Generated `ApplicationPolicy` ships `Context = TenancyDable::Policy::Context` (plus a commented `pundit_user` example), so a host's `ApplicationPolicy::Context.new(...)` resolves after adoption. **Generated-template change only** — no runtime lib surface change. | `spec/generators/install_generator_spec.rb` (9→10) | +1 |
| **B** | New `config.on_not_a_member` setting: `:not_a_member_error` (default — raise `NotAMemberError`, today's behavior), `:not_authorized` (raise `Pundit::NotAuthorizedError`), or a callable `->(tenant)` run in the controller. `Configuration#validate!` rejects an unknown symbol. The **14th** setting; `Resolvable`'s membership-missing branch dispatches on it. | `spec/resolution/not_a_member_behavior_spec.rb` (new, 5) + `spec/contract_spec.rb` (60→62) | +7 |
| **C** | `CrossTenantError::MESSAGE = "belongs to a different tenant"` — the previously-dead class is now the single source of truth for the cross-tenant `belongs_to` validation string; `Scoped` references it. Validation still **adds** the error (does not raise); string byte-for-byte unchanged. Additive constant; error count stays 8. | `spec/scoping/cross_tenant_spec.rb` (3→4) | +1 |

The two **UPGRADING gaps** the v0.1.0 review named are now folded into
[UPGRADING.md §3](UPGRADING.md): the `ApplicationPolicy::Context` alias note (Fix A)
and the `rescue_from TenancyDable::NotAMemberError` / `on_not_a_member = :not_authorized`
guidance for non-members (Fix B; messages are English — localize in the rescue).
`CHANGELOG.md` carries the dated `[0.2.0]` entry. As with the v0.1.0 build, the work
is **uncommitted** pending the maintainer's commit/tag (`v0.2.0`).

---

## v0.3.0 addendum (Action Cable + Job membership) — 2026-06-05

A lean 6-phase follow-up that makes the gem first-class with **Action Cable** and
closes the one gem-side **ActiveJob caveat** — two **additive** features → a MINOR
bump `TenancyDable::VERSION` `0.2.0` → **`0.3.0`**. Default behavior is unchanged, so
no host breaks; the frozen public surface holds except as recorded in
[DESIGN.md §14](DESIGN.md). The error hierarchy stays at **8 classes** and config
settings stay at **14** — the Channel concern reuses `slug_param` and adds no
setting, no error class. Work landed on branch `feat/v0.3.0-action-cable`.

**Suite: `bundle exec rspec` green — 285 examples, 0 failures** (was 260 at v0.2.0;
**+25** across the v0.3.0 run):

| Feature | Change | New/changed spec | Δ examples |
|---|---|---|---:|
| **Action Cable** | New opt-in `TenancyDable::Channel` (`lib/tenancy_dable/channel.rb`) — the Cable parallel to `Controller::Resolvable`: resolves the tenant **by slug** per subscription (invariant 5), enforces membership (`reject_unless_member!`), streams tenant-namespaced names (`stream_for_tenant` → `"tenant:<id>"`), and auto-scopes **every** channel action by wrapping `perform_action`. **Not** auto-required (Action Cable stays optional); the gem does **not** own Cable auth — the host's `ApplicationCable::Connection` declares `identified_by :current_user` and the concern only *reads* it. | `spec/channels/tenant_channel_spec.rb` (new, `type: :channel`) + the Cable harness (Combustion boots `:action_cable`; connection/channel fixtures + `cable.yml` under `spec/internal/`) | +8 |
| **Job membership** | `TenancyDable::Job` now carries the acting **membership** alongside the tenant: a second namespaced payload key (`SERIALIZED_MEMBERSHIP_KEY = "tenancy_dable_membership_id"`) is serialized at enqueue and `current_membership` is restored for `perform` — set **inside** the existing `with_tenant` block, so its `ensure` tears tenant **and** membership down together (no leak). Backward compatible: an older payload restores a nil membership; tenant propagation byte-for-byte unchanged. | `spec/integration/active_job_propagation_spec.rb` (6 → 10) + job-membership unit/contract coverage | +10 |
| **Contract lock** | `spec/contract_spec.rb` adds `TenancyDable::Channel` to the frozen surface — a concern exposing the six frozen helpers (`current_tenant`, `current_membership`, `tenant_member?`, `reject_unless_member!`, `stream_for_tenant`, `with_tenant_context`), locked by responds-to (mirroring the `Job` seam lock). The necessarily-public `#perform_action` wrapper is intentionally **not** in the frozen six. Error count (8) and settings count (14) re-asserted unchanged. | `spec/contract_spec.rb` (63 → 70) | +7 |

**A cross-phase correctness note (Action Cable dispatch):** `Channel#perform_action`
**must be public.** Action Cable dispatches actions through an *explicit receiver*
(`subscription.perform_action(data)` — both at runtime via
`ActionCable::Connection::Subscriptions` and in the channel `TestCase`), so a private
override raises `NoMethodError` and breaks **all** channel dispatch. The shipped
concern keeps it public (with a comment explaining why); `DESIGN.md §14.1` — which
had shown it under `private` and noted phase 02 "may keep it private" — was
reconciled to the now-real public method in the docs phase. It is **not** part of the
frozen surface (the six helpers are), so the contract lock is unaffected.

`CHANGELOG.md` carries the dated `[0.3.0]` entry (Added: `Channel`; Changed: `Job`
carries membership); `README.md` gains an "Action Cable tenant resolution" section
and a membership note on the ActiveJob section; `UPGRADING.md` gains the Channel
adoption note (gem does not own connection auth) and the Job-membership behavior
change. The critic phase (below) commits the verified changeset to
`feat/v0.3.0-action-cable`; the release **tag** (`v0.3.0`), push, and publish remain
the maintainer's step.

### Critic / verify (phase 05) — final adversarial gate

Final skeptical pass: prove both features and the **absence** of regressions, then
land the changeset. `bundle exec rake` (RSpec + Standard) is **green — 286 examples,
0 failures, 0 Standard offenses**, order-independent across seeds (1 / 12345 /
random). The count is **+1** over the phase-04 addendum's 285: the critic added one
adversarial channel example (slug-only proven end-to-end on the Cable path, below).

**Per-feature proof (adversarial):**

| Claim under attack | Proof |
|---|---|
| **Cable — member subscribes, streams `tenant:<id>`** | `spec/channels` — confirmed subscription + `have_stream_from("tenant:#{tenant.id}")` (id-namespaced, never keyed off the slug). |
| **Cable — non-member / member-of-B / unknown slug / absent slug all rejected** | Four reject cases; a member of tenant B (even as *owner*) is rejected reaching A's slug — no nil tenant ⇒ no membership ⇒ `reject`. |
| **Cable — slug-only (invariant 5) on the channel path** | **New** case: a tenant's own member, subscribing with its numeric **id** in the slug slot, is **rejected** (`find_by(slug:)` never matches an id). The Cable parallel to `spec/resolution/slug_only_spec.rb`. |
| **Cable — action is tenant-scoped, no context leak** | `perform :widget_count` sees A's 2 rows (table holds 3 incl. B's); inside-action `current_tenant == tenant_a`; after dispatch `current_tenant`/`current_membership` both nil (auto-`perform_action` wrap + `with_tenant` ensure). |
| **Job — `perform` restores tenant AND membership; no leak; backward-compatible** | `spec/integration/active_job_propagation_spec.rb` — restores both from the payload; membership-less (pre-v0.3.0) payload restores nil membership with tenant unchanged; nothing set after `execute`. Tenant-only propagation (capture → restore → scoped read → fail-open nil) still passes. |

**Guardrails held (re-verified):**
- **No host/skeleton file touched** — the repo root *is* the gem; `git status` shows only `lib/`, `spec/`, and gem docs. No reference to the host app (`ror_saas_multitenant_test`, its `Current`, `Agents::RunJob`, or its `TenantChannel`) in shipped code — the only "skeleton" hits in `lib/` are descriptive comments.
- **Gem does not own Cable auth** — `Channel` reads `current_user` only; no cookie/session/token/`request`/`env` parsing (the sole "cookie/session" mention is a comment explaining the *host's* job). Ships no `Connection` auth concern.
- **Inherent Job seams unchanged** — tenant captured at *enqueue* (`serialize`); a *deleted* tenant reloads to nil via `find_by(id:)` ⇒ `with_tenant(nil)` (fail-open). The membership extends the same seam symmetrically (deleted membership ⇒ nil), inside the same `with_tenant` block.

**Six security invariants — no regression:** `spec/security/red_team_spec.rb` green (9
examples); invariant 5 (slug-only) now additionally proven **on the new Channel path**
end-to-end.

**Contract consistency:** `spec/contract_spec.rb` includes `TenancyDable::Channel`
(six frozen helpers, responds-to lock); error hierarchy **8** classes; settings **14**;
`VERSION = "0.3.0"` (`version.rb`) and dated `[0.3.0]` entry in `CHANGELOG.md`.

**Committed** on `feat/v0.3.0-action-cable` — **not** `master`/`main`. Tag/push/publish
left to the maintainer.
