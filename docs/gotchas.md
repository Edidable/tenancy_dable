# Gotchas

> Traps in THIS gem that cut across domains. A gotcha earns a place here only when it spans more than one domain and names something in the repository (a file, a setting, a spec). A trap that belongs to one domain lives in that domain's doc under its own heading, and a lesson about a machine, a tool outside the repo or a library in general is not a gotcha of this gem and does not belong in `docs/`.

## How to Use

Each gotcha is a `### Gotcha: <short title>` heading plus one paragraph: [SYMPTOM:...], [CAUSE:...], [FIX:...] and, when there is one, a [RULE:...]. Before adding one, grep `docs/` for its key term, and ask whether it belongs in a domain doc instead; this file is the last resort, not the default.

## Domain Gotchas (pointers)

Documented inside the domain docs; listed here only so you know where to look when something breaks:

- Scoping: the default scope alone cannot stop `a.widgets` from reading another tenant, the pin classifier and the read-guard residuals, the foreign-tenant write refusal, the upsert conflict-target rule, and `increment!` / `update_counters` / `counter_cache` raising `BulkWriteError` inside a tenant - `docs/domains/scoping.md` and its spokes `docs/domains/scoping/default-scope.md`, `docs/domains/scoping/read-guard.md`, `docs/domains/scoping/write-guard.md`
- Context: fiber isolation, the `snapshot`/`carry` carrier, fail-open threads with `require_tenant` off, and the audited `without_tenant` - `docs/domains/context.md`, `docs/domains/context/fiber-safety.md`, `docs/domains/context/bypass.md`
- Jobs: a vanished tenant raises `TenantNotFoundError` and a deleted membership reloads to nil - `docs/domains/jobs.md`
- Locale files: the order of `I18n.load_path`, and `pt-BR` loading only when the host declares it early enough - `docs/domains/i18n.md`
- Declarations and the audit: one declaration per lineage, the scoped-table twin, what the audit skips, and a global base class silencing it - `docs/domains/declarations.md`
- Identity: why Membership is not scoped and the last-owner guard - `docs/domains/identity.md`
- Resolution and Cable: slug-only lookup, `on_tenant_not_found`, `on_not_a_member` - `docs/domains/resolution.md`
- Boot: why the controller concern is prepended, and the order of the Active Record installs - `docs/domains/boot.md`
- The harness: one SQLite database per checkout, so never two rspec processes in one checkout, and the isolation-level toggling cautions - `docs/domains/testing.md`
- Releases: the lockfile is not committed, so lint resolves the newest `standard`, and `rake release` would publish to RubyGems - `docs/domains/release.md`

## Cross-Domain Gotchas

### Gotcha: Direct `Current` writes skip every hook

[SYMPTOM:a `TenancyDable::Current.set(tenant: t)` or `Current.tenant = t` works in a console but raises no `UnsafeIsolationError`, logs no override and fires no RLS statement]. [CAUSE:the isolation check runs in every facade writer (`current_tenant=`, `current_membership=`, `without_tenant`, and through them `with_tenant` and `Snapshot#restore`), the audit-override policy and the RLS statement run in `current_tenant=` only, and `Current` is only raw state]. [FIX:write through the facade: `TenancyDable.current_tenant=`, `with_tenant`, `without_tenant`, or `Snapshot#restore` for a carried context]. [RULE:never write `TenancyDable::Current` directly; a direct write is a documented bypass of three guards at once, not a guarded path]. The domains involved are `context` (which owns the RLS hook) and `jobs` (which restore through `with_tenant`).

### Gotcha: A lost context is fail-open unless `require_tenant` is on

[SYMPTOM:a scoped read in a `Thread.new`, a thread-pool task, an `Enumerator#next` body or an `Async` task returns every tenant's rows, with no exception]. [CAUSE:`Current` is isolated per thread or fiber, so work spawned from a request starts with no tenant; with [CONFIG:require_tenant = false] the default scope takes its fail-open branch and the read guard has no current tenant to compare against]. [FIX:set [CONFIG:require_tenant = true] and hand the context over on purpose with `Thread.new(&TenancyDable.carry { ... })` or `executor.post(&TenancyDable.carry { ... })`]. [RULE:a host that runs threads, a pool or fibers turns `require_tenant` on; the same applies to a rake task or console that must not read across tenants]. The domains involved are `context`, `scoping` and `jobs`; the decision behind the default is in `docs/decisions.md`.

### Gotcha: A nil `current_membership` is not a system context

[SYMPTOM:a policy or controller that treats a nil `current_membership` as "no user, so allow" grants access inside `with_tenant(other)` or `with_tenant(nil)` while a membership is stored]. [CAUSE:`current_membership` returns the stored membership only while its tenant id is the current tenant's, so a membership that belongs to another tenant, or any membership with no tenant current, reads as nil while it is still stored]. [FIX:check `TenancyDable.foreign_membership?` as well, which is true when a membership is stored but is not the current tenant's]. [RULE:never read a nil membership as an absence of identity; read it with `foreign_membership?`]. The domains involved are `context`, `jobs` (which carry the stored membership, not the reader's value), `authorization` and `resolution`.

### Gotcha: `tenant_fk` is not honoured by the identity and policy helpers

[SYMPTOM:with a non-default [CONFIG:tenant_fk], scoped models filter correctly but `same_tenant?` in a policy is false for a record without a `tenant_id` method, and the membership uniqueness, last-owner and membership lookups still read `tenant_id`]. [CAUSE:`belongs_to_tenant`, the guards, `Policy::Base::Scope` and the audit read the configured column, while `MembershipModel`, `UserModel#membership_for`, `TenancyDable.current_membership` and `Policy::Base#same_tenant?` name `tenant_id` literally; the model generator honours a custom column in its migration only]. [FIX:keep the memberships table and any record a policy compares on a `tenant_id` column, and use the configured name only on the models you scope]. [RULE:before changing `tenant_fk`, grep `lib/tenancy_dable/models/`, `lib/tenancy_dable/policy/` and `lib/tenancy_dable.rb` for `tenant_id` and decide each site]. The domains involved are `configuration`, `identity`, `authorization`, `generators` and `scoping`.

### Gotcha: An identity concern plus a declaration raises

[SYMPTOM:a model that does `include TenancyDable::TenantModel` (or `UserModel`, `MembershipModel`) and then calls `tenant_global` or `belongs_to_tenant` raises `ConfigurationError` at class load]. [CAUSE:each identity concern declares its model global as the first statement of its `included` block, and a second declaration anywhere on a lineage is refused]. [FIX:remove the host's own declaration, because the concern's is the model's declaration; to change what it says, do not include the concern and write the model yourself]. [RULE:a model includes either a gem identity concern or its own declaration, never both]. The domains involved are `identity`, `declarations` and `generators` (the install generator tells the host which concerns to include).

### Gotcha: The guards hook Active Record internals that differ by Rails line

[SYMPTOM:the suite is green on the default Rails line and red on another cell of the CI matrix, with `ArgumentError`, `NoMethodError` on an Arel node, or a hook that no longer runs]. [CAUSE:the Relation guard overrides `exec_queries`, `perform_calculation`, `compute_cache_version` and `arel`, the `InsertAll` guard overrides `initialize`, and the pin classifier walks Arel node shapes (`Or` exposes `left` and `right` on the oldest supported line and `children` on the later ones); these are `:nodoc:` Active Record internals, not a public API]. [FIX:keep forwarding with `(...)`, walk nodes by duck typing, and run the change against every Rails line the CI matrix lists]. [RULE:`spec/contract_spec.rb` locks the extension's method lists and their visibility, and checks `compute_cache_version` and `arel` against Active Record's own public visibility, so a Rails line that changes either fails it on purpose; for the other hooks the CI matrix is what catches a change, so a change to `relation_extension.rb` or `insert_all_extension.rb` is not done until the other lines are green]. The domains involved are `scoping`, `boot`, `testing` and `release`.

### Gotcha: A public-surface change touches several files

[SYMPTOM:`spec/contract_spec.rb` fails right after adding or removing a setting, or after removing a listed error, facade method or hooked Relation method, while a NEW error, facade method or hook passes it silently, and a host's generated initializer lacks the new setting]. [CAUSE:the contract spec derives its settings check from the code (it counts `Configuration`'s writers) but checks errors, facade methods, hooks and helpers against explicit lists, and the same fact is mirrored in the README tables, the install generator's initializer template and the `DESIGN.md` contract]. [FIX:add the new symbol to the spec's list, the README table, the generator template and a `DESIGN.md` delta together]. [RULE:a new error also goes in the README errors table, a new setting also goes in the generator template and the README settings table and gets a rule in `Configuration#validate!`]. The domains involved are `errors`, `configuration`, `generators`, `testing` and `release`.
