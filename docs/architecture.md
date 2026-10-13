# Architecture

> How the layers of `tenancy_dable` fit together, and the security invariants the gem owns with the spec that proves each one. The per-symbol contract is frozen in `DESIGN.md`; the behaviour of each layer is in its domain hub under `docs/domains/`.

## Shape of the Gem

`tenancy_dable` is a single versioned dependency that gives a Rails host four things: a row-scoping engine, a multi-workspace identity model, slug-based tenant resolution with membership enforcement, and a Pundit authorization context. The scoping engine is [CHOICE:self-contained]: the gem owns its security boundary and does not depend on a third-party tenancy gem (see `docs/decisions.md`). Everything contextual (the current tenant, the bypass flag, whether `require_tenant` is truthy) is read at QUERY time from [CLASS:TenancyDable::Current] and the configuration, and everything structural (the foreign-key column, the association) is bound ONCE when a model declares itself scoped, exactly like a plain `belongs_to` binds its key.

The gem integrates through a railtie, not an engine: [FILE:lib/tenancy_dable/railtie.rb] wires every framework hook, so the entry file [FILE:lib/tenancy_dable.rb] requires the errors, configuration, facade support, policy and the railtie, and the railtie requires the Active Record and Action Controller files lazily when those frameworks load. Boot order and the opt-in files are in [FILE:docs/domains/boot.md].

## The Layers

Each layer has one file family, one domain hub and one same-named rule.

- The scoping engine is the model-side concern [MODULE:TenancyDable::Scoped] in [FILE:lib/tenancy_dable/scoped.rb] (`belongs_to_tenant`, the default scope, tenant assignment, immutability, the cross-tenant `belongs_to` validation, the foreign-tenant write refusal), the Relation guards in [FILE:lib/tenancy_dable/relation_extension.rb] (the read guard and the bulk-write guard, sharing one pin classifier), and the bulk-insert guard in [FILE:lib/tenancy_dable/insert_all_extension.rb]. Hub: [FILE:docs/domains/scoping.md].
- The context facade is the `TenancyDable` module itself plus [CLASS:TenancyDable::Current] in [FILE:lib/tenancy_dable/current.rb] and [CLASS:TenancyDable::Snapshot] in [FILE:lib/tenancy_dable/snapshot.rb]. `Current` holds raw state only; every behaviour (the audit-override policy, the RLS hook, the isolation check, `with_tenant`, `without_tenant`) lives on the facade so there is a single mutation path. Hub: [FILE:docs/domains/context.md].
- The identity concerns [MODULE:TenancyDable::TenantModel], [MODULE:TenancyDable::UserModel] and [MODULE:TenancyDable::MembershipModel] in [FILE:lib/tenancy_dable/models/] give the host its `Tenant`, `User` and `Membership`. Membership is deliberately not tenant-scoped. Hub: [FILE:docs/domains/identity.md].
- Slug resolution is [MODULE:TenancyDable::Controller::Resolvable] in [FILE:lib/tenancy_dable/controller/resolvable.rb], prepended onto `ActionController::Base`; it finds the tenant by slug, requires a membership, and publishes both through the facade. Hub: [FILE:docs/domains/resolution.md].
- Authorization is [CLASS:TenancyDable::Policy::Context] and [CLASS:TenancyDable::Policy::Base] with its `Scope` in [FILE:lib/tenancy_dable/policy/]. Policies decide on the user, tenant and membership triple, and the base policy denies every action until a subclass grants it. Hub: [FILE:docs/domains/authorization.md].
- Action Cable support is the opt-in concern [MODULE:TenancyDable::Channel] in [FILE:lib/tenancy_dable/channel.rb], the Cable parallel of `Resolvable`; the gem owns no Cable authentication. It is documented with resolution in [FILE:docs/domains/resolution.md].
- Job propagation is the opt-in concern [MODULE:TenancyDable::Job] in [FILE:lib/tenancy_dable/job.rb], which carries the tenant id and membership id through the serialized payload and restores them around `perform`. Hub: [FILE:docs/domains/jobs.md].
- Declared tenancy and its audit are [MODULE:TenancyDable::Declarations] in [FILE:lib/tenancy_dable/declarations.rb] and [MODULE:TenancyDable::Audit] in [FILE:lib/tenancy_dable/audit.rb], with the rake task in [FILE:lib/tenancy_dable/tasks/audit.rake]. Hub: [FILE:docs/domains/declarations.md].
- Localizable validation messages are the locale files in [FILE:lib/tenancy_dable/locale/], registered by the railtie. Hub: [FILE:docs/domains/i18n.md].
- Configuration and errors are the two vocabularies every layer shares: [FILE:lib/tenancy_dable/configuration.rb] and [FILE:lib/tenancy_dable/errors.rb]. Hubs: [FILE:docs/domains/configuration.md] and [FILE:docs/domains/errors.md].
- The generators in [FILE:lib/generators/] wire a host to the gem. Hub: [FILE:docs/domains/generators.md].

## How a Request Flows Through the Layers

A host controller opts in with `resolve_tenant!`. Its before-action reads only the slug parameter, looks the tenant up by slug, asks the acting user for the membership in that tenant, and refuses the request through `on_not_a_member` when there is none. Only then does it publish [METHOD:TenancyDable.current_tenant=] and [METHOD:TenancyDable.current_membership=], the one place the isolation check, the audit-override policy and the RLS hook run.

From that point every query on a model that called `belongs_to_tenant` passes through two gates. The default scope adds `tenant_id = current` at SQL-build time, and the Relation guards inspect the finished relation at execution time, because the default scope alone does not hold when a relation is merged, rewritten or built through another record's association (see [FILE:docs/domains/scoping/read-guard.md]). Writes pass through the callbacks and overrides in `Scoped` for records and through the Relation and `InsertAll` prepends for bulk paths. Policies then decide on a `Policy::Context` built with [METHOD:TenancyDable.pundit_context], and a policy scope fails closed.

Work that leaves the request (a job, a Cable action, a thread) crosses a boundary where the context does not travel on its own. `Job` and `Channel` restore the context through the facade, and a host's own threads and fibers hand it across with [METHOD:TenancyDable.carry] (see [FILE:docs/domains/context/fiber-safety.md]). A deliberate cross-tenant operation is the audited [METHOD:TenancyDable.without_tenant] (see [FILE:docs/domains/context/bypass.md]).

## Two Mutation Rules the Whole Gem Relies On

All tenant state is written through the facade. The isolation check runs in every facade writer ([METHOD:TenancyDable.current_tenant=], [METHOD:TenancyDable.current_membership=], [METHOD:TenancyDable.without_tenant], and through them `with_tenant` and `Snapshot#restore`); the audit-override policy and the RLS statement run in `current_tenant=` only, which `with_tenant` and `Snapshot#restore` go through. A write straight to `TenancyDable::Current` skips all three, and the gem documents that as a bypass, not a guarded path.

Guards judge a relation by what it pins, never by what it was built from. One private classifier, [METHOD:tenancy_pin_state], answers `:current`, `:other`, `:removed` or `:unpinned` for a relation, and both the read guard and the bulk-write guard consume it so the pin they reason about cannot drift. The details are in [FILE:docs/domains/scoping/read-guard.md].

## Security Invariants

The boundary this gem owns is the list of invariants below, stated in `DESIGN.md` §11 and amended in §16. Each is stated here in system terms with the spec that proves it. `README.md` repeats the list for hosts.

### Invariant 1: fail-closed when configured

With [CONFIG:require_tenant] truthy (a plain value, or a callable evaluated in context), a query on a scoped model with no current tenant raises [ERROR:TenancyDable::NoTenantError] instead of returning every tenant's rows. The default scope decides at query time. The gem's default is [CONFIG:require_tenant = false], which keeps the default scope fail-open for consoles and migrations that run with no tenant, so the invariant holds exactly when the host turns it on (the rationale is in `docs/decisions.md`). Proven by [SPEC:spec/scoping/default_scope_spec.rb] (the fail-closed examples, including the callable form) and the first invariant block of [SPEC:spec/security/red_team_spec.rb], which checks every read entry point. The details are in [FILE:docs/domains/scoping/default-scope.md].

### Invariant 2: no cross-tenant read or write path

The default scope filters by tenant before any ordering. On top of it, four mechanisms close the paths the default scope cannot see:

- A read pinned to another tenant, or whose tenant filter was removed, raises [ERROR:TenancyDable::CrossTenantReadError] while a tenant is current. [CONFIG:guard_reads] switches it off.
- A bulk write (`update_all`, `delete_all`, `destroy_all`) that is not provably pinned to the current tenant raises [ERROR:TenancyDable::BulkWriteError]; `without_tenant` is the explicit bypass.
- A create, update, destroy, `touch`, `delete` or `update_columns` into or of another tenant's record, and an `insert_all` or `upsert_all` that could reach one, raises [ERROR:TenancyDable::CrossTenantWriteError]. There is no setting for it: it is a rule, with `with_tenant(target)` as the local escape.
- A `belongs_to` from one scoped record to another tenant's record adds a validation error, because its input plausibly comes from a form.

Resolution enforces membership before any tenant is published. Proven by [SPEC:spec/scoping/read_guard_spec.rb], [SPEC:spec/scoping/bulk_write_guard_spec.rb], [SPEC:spec/scoping/create_refusal_spec.rb], [SPEC:spec/scoping/foreign_record_write_spec.rb], [SPEC:spec/scoping/insert_all_guard_spec.rb], [SPEC:spec/scoping/cross_tenant_spec.rb], [SPEC:spec/resolution/membership_enforcement_spec.rb], [SPEC:spec/integration/cross_tenant_isolation_spec.rb], and the adversarial examples in [SPEC:spec/security/red_team_spec.rb] (including the read through the tenant's own association).

The invariant is true within documented residuals. [RESIDUAL:a relation whose where clause no longer mentions the tenant column and that recorded no removal] is indistinguishable from `Model.unscoped` and passes: `Model.unscoped` itself, `except(:where)`, `only(...)` without `:where`, and an `or` with such a relation. [RESIDUAL:SQL-string predicates and raw SQL] (`where("tenant_id = ?", x)`, a SQL-string `update_all`, `find_by_sql`) are invisible to a guard that reads Arel nodes. [RESIDUAL:`reload` by id] runs inside `unscoped` and reads the row the record already is. [RESIDUAL:the cache key of an already-loaded association target] runs no query. All of these are explicit relation surgery; the guards target the shapes Active Record produces on its own (association merge, `rewhere`, `merge`, `unscope`, `or`). `unscoped` stays the explicit Active Record bypass on purpose (see `docs/decisions.md`).

### Invariant 3: the tenant column is immutable after create

Reassigning the tenant of a persisted record raises [ERROR:TenancyDable::TenantImmutableError] on every path the gem can see: the column writer, the association writer (caught at save time), `update_columns` and `update_column`, and an `update_all` whose Hash names the tenant column (aliases and case variants resolved). Setting it on a new record is allowed, and writing the same value is a no-op. Proven by [SPEC:spec/scoping/tenant_assignment_spec.rb], [SPEC:spec/scoping/foreign_record_write_spec.rb], [SPEC:spec/scoping/bulk_write_guard_spec.rb] and the third invariant block of [SPEC:spec/security/red_team_spec.rb]. [RESIDUAL:a SQL-string `update_all`] names no column the gem can see.

### Invariant 4: the Pundit scope fails closed

`Policy::Base::Scope#resolve` returns `scope.none` when the context has no tenant, and otherwise filters by the configured tenant column. A policy that forgets to define an action denies it. Proven by [SPEC:spec/policy/scope_spec.rb] and [SPEC:spec/policy/secure_by_default_spec.rb]. The details are in [FILE:docs/domains/authorization.md].

### Invariant 5: slug-only resolution

Resolution reads `params[slug_param]` and looks the tenant up by its `slug`; it never reads a tenant id from the URL, so a numeric id in the slug position simply fails to resolve. The Cable concern follows the same rule with a non-bang lookup that rejects the subscription. Proven by [SPEC:spec/resolution/slug_only_spec.rb] and [SPEC:spec/channels/tenant_channel_spec.rb]. The details are in [FILE:docs/domains/resolution.md].

### Invariant 6: no payload leakage

Everything the gem logs, raises or emits carries tenant ids, never a record payload. Every guard message (the scoping, write, bulk and insert refusals, the audit override, the isolation check and the job's vanished tenant) names the model and tenant ids only. [ERROR:TenancyDable::NotAMemberError] names the tenant slug the request carried, and [ERROR:TenancyDable::ConfigurationError] names the offending setting value; neither carries a record or its attributes. The [EVENT:without_tenant.tenancy_dable] payload has exactly three keys (`reason`, `tenant_id`, `call_site`); it is instrumented without a block so a raising block cannot add its exception, which may carry a record, to the payload, and a `reason:` that is not nil, a String or a Symbol is refused before the event. Hosts must not put record data in a reason. The gem persists nothing. Proven by [SPEC:spec/facade/without_tenant_audit_spec.rb] and the sixth invariant block of [SPEC:spec/security/red_team_spec.rb]. The details are in [FILE:docs/domains/context/bypass.md].

### Invariant 7: no shared tenant state across fibers

Under a fiber scheduler with thread isolation, every fiber on a reactor thread would share one `Current`, a live cross-request leak. Every gem write to tenant state runs the isolation check first and raises [ERROR:TenancyDable::UnsafeIsolationError] by default ([CONFIG:isolation_check] can be `:warn` or `:off`). Proven by [SPEC:spec/facade/isolation_check_spec.rb] for each writer and by the real-reactor example there; the carrier is proven by [SPEC:spec/facade/snapshot_spec.rb]. The invariant covers state the gem writes; a lost context in a host's own thread is a different problem, described next. The details are in [FILE:docs/domains/context/fiber-safety.md].

## What the Invariants Do Not Promise

A thread or fiber that starts with no tenant is not fail-closed on its own. With [CONFIG:require_tenant = false] the default scope takes its fail-open branch and the thread reads every tenant's rows, and nothing refuses it because the read guard has no current tenant to compare against. Only [CONFIG:require_tenant = true] turns the lost context into [ERROR:TenancyDable::NoTenantError]. A host that runs threads, a pool or fibers sets `require_tenant` on and hands the context across with `carry` (the rationale is in `docs/decisions.md`).

Membership is the other deliberate gap in scoping. [MODULE:TenancyDable::MembershipModel] declares itself global with `allow_tenant_fk: true` because resolution queries it before any tenant is current; a query on it ignores the current tenant entirely. [SPEC:spec/identity/membership_not_scoped_spec.rb] locks that it stays queryable with no tenant and under `require_tenant`.

## Where to Look Next

- Why each design choice was made and what was rejected: `docs/decisions.md`.
- Conventions every file follows: `docs/patterns.md`.
- Traps that cross domains: `docs/gotchas.md`.
- The runtime and development dependencies: `docs/stack.md`.
