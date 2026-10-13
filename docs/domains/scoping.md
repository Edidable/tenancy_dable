# Scoping: row-level tenant isolation

Scoping is the engine that keeps one tenant's rows away from another: a model declares itself tenant-scoped with [MACRO:belongs_to_tenant], and from then on every read is filtered to the current tenant, every bulk write must be pinned to it, and a write that names another tenant's row is refused. It is the security core of the gem. The code lives in three files: [FILE:lib/tenancy_dable/scoped.rb] (the model concern: the macro, the default scope, the record-write refusals), [FILE:lib/tenancy_dable/relation_extension.rb] (a module prepended to `ActiveRecord::Relation`: the read guard, the bulk-write guard and the pin classifier both consume) and [FILE:lib/tenancy_dable/insert_all_extension.rb] (a module prepended to `ActiveRecord::InsertAll`). The railtie wires the prepends; see [REF:boot.md]. The frozen contract is `DESIGN.md` §5, amended by §16.1 and §16.2.

## Spokes

- [SPOKE:docs/domains/scoping/default-scope.md] holds what the macro installs, the default scope's decision tree, the `BuiltWithoutTenant` marker, the tenant column's auto-assign and immutability, the cross-tenant `belongs_to` validation and per-tenant uniqueness.
- [SPOKE:docs/domains/scoping/read-guard.md] holds the read hooks, the four-state pin classifier with its exact order and list rules, the nil-pin exception, what is refused and what passes, and the documented residuals.
- [SPOKE:docs/domains/scoping/write-guard.md] holds the bulk-write guard, the refusal to write a record of another tenant, the `insert_all` / `upsert_all` guard and the refusals that stop the tenant column from being rewritten.

## The layers and what each one stops

Isolation is enforced by four layers, each with a different blind spot, so none is optional. A layer reads the current tenant and the bypass flag from [CLASS:TenancyDable::Current] at the moment it runs, never from state captured earlier; how that state is set and cleared is the facade's job ([REF:context.md]).

- [LAYER:default scope] filters every relation built for a scoped model to `tenant_fk = current tenant`, or raises when `require_tenant` is truthy and no tenant is current. Its blind spot: an association's relation replaces the filter (Active Record's `WhereClause#merge` drops the receiver's predicate on a column the other side constrains), and `unscope` or `unscoped` removes it. That blind spot is why the next layer exists.
- [LAYER:read guard] refuses a read whose tenant filter points at another tenant or was removed. Its blind spot is explicit relation surgery that leaves no trace in the where clause (the residuals in [SPOKE:docs/domains/scoping/read-guard.md]).
- [LAYER:bulk-write guard] refuses `update_all`, `delete_all` and `destroy_all` unless the relation is provably pinned to the current tenant, and refuses an `update_all` that rewrites the tenant column.
- [LAYER:record-write refusals] refuse a create, update, destroy, `touch`, `delete`, `update_columns` and batch insert whose record belongs to another tenant, and make the tenant column immutable after create.

Authorization (Pundit scopes that fail closed to `none`) is a fifth, separate layer outside this domain; see [REF:authorization.md].

## Principles

[RULE:the default is fail-open, and fail-closed is a choice]. With `require_tenant` false (the default), a query with no current tenant reads every row of a scoped model; a host that wants a hard stop sets `require_tenant` truthy (a boolean or a callable) and every scoped query with no tenant raises `NoTenantError`. A request that resolves a tenant has one before the action runs ([REF:resolution.md]); a workspace-less request (`on_tenant_not_found = :null`, or a controller without `resolve_tenant!`) is in the fail-open case like a job or a console, and `require_tenant` is the backstop for all of them. A thread or fiber that lost the context is in the fail-open case too, which [REF:context.md] covers.

[RULE:there are two explicit bypasses and nothing quiet]. `TenancyDable.without_tenant` turns scoping, the read guard, the bulk-write guard, the foreign-tenant refusals and the batch-insert guard off for a block, and is audited; it does not lift the immutability of the tenant column on a record (the column writer, the save-time backstop, `update_columns` and `update_column`), and only the Hash `update_all` rewrite refusal steps aside inside it ([REF:context.md]). `Model.unscoped` with no tenant predicate is Active Record's own bypass and the gem keeps it working because Active Record itself depends on it (uniqueness validation, `reload`); a documented residual of the read guard, never a silent one.

[RULE:one classifier serves both guards]. The read guard and the bulk-write guard both call [METHOD:tenancy_pin_state], so what each reasons about cannot drift. The bulk-write guard accepts only the `:current` state; the read guard refuses `:other` and `:removed`.

[RULE:guards are decision trees with ids-only messages]. Every refusal message of these guards names the model and tenant ids, never a record, an attribute value or a slug, so a log line cannot leak tenant data. The errors raised are [ERROR:TenancyDable::NoTenantError], [ERROR:TenancyDable::CrossTenantReadError], [ERROR:TenancyDable::BulkWriteError], [ERROR:TenancyDable::CrossTenantWriteError] and [ERROR:TenancyDable::TenantImmutableError]; the whole list and the hierarchy are in [REF:errors.md] and locked by [SPEC:spec/contract_spec.rb].

[RULE:a guard raises instead of returning an empty set]. Code that pins another tenant is a bug whether it gets nothing or something back. The escape is local and explicit: `with_tenant(other) { ... }` to act inside the right tenant, or `without_tenant(reason:) { ... }` for a deliberate cross-tenant operation.

## Settings and declarations the domain reads

The settings are [CONFIG:tenant_fk] (the column name, default `tenant_id`), [CONFIG:require_tenant] and [CONFIG:guard_reads]; their defaults and validation are in [REF:configuration.md]. The macro also registers the model's tenancy declaration, which makes a second declaration raise and lets `TenancyDable.audit` prove no model was forgotten ([REF:declarations.md]). Membership is deliberately not scoped, because it is queried before any tenant is known ([REF:identity.md]). The validation message for a cross-tenant `belongs_to` and the translation keys are in [REF:i18n.md].

## Where the proof lives

The scoping behaviour is proved under [DIR:spec/scoping/], one spec per concern: the default scope, tenant assignment and immutability, the cross-tenant validation, per-tenant uniqueness, the read guard, the bulk-write guard, the create refusal, the foreign-record writes and the `insert_all` guard. [SPEC:spec/security/red_team_spec.rb] attacks the invariants from outside with each entry point at once. The fixture models those specs use (a scoped `Widget` with a uniqueness validation and a self reference, a scoped `Gadget` with none, and the unscoped `Tenant`) are defined in the Combustion harness described in [REF:testing.md]. [RULE:a scoping change names the spec that proves it]; a guard that changes what it refuses changes an example in these files in the same commit.

## When you change this domain

If you change what the classifier returns, also change both guards' tests: the read guard's examples in [SPEC:spec/scoping/read_guard_spec.rb] and the bulk-write examples in [SPEC:spec/scoping/bulk_write_guard_spec.rb] share it. If you add a read entry point to the Relation hooks, add the example to the association-read list and check [SPEC:spec/contract_spec.rb] for the override list and its visibility. If you add a new refusal error, the error hierarchy rule in [REF:errors.md] applies. The load-bearing traps are in the spokes: `where_values_hash` in [SPOKE:docs/domains/scoping/read-guard.md], the `InsertAll#initialize` signature in [SPOKE:docs/domains/scoping/write-guard.md], and the fail-closed `Model.new` in [SPOKE:docs/domains/scoping/default-scope.md].
