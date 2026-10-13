# Scoping: the read guard

> Part of the [scoping domain](../scoping.md).

This spoke covers the guard that refuses a read of a scoped relation whose tenant filter points at another tenant or was removed, while a tenant is current. The code is the read half of [FILE:lib/tenancy_dable/relation_extension.rb]; the contract is frozen in `DESIGN.md` §16.1. The classifier it shares with the bulk-write guard is described here; the write side is in [SPOKE:docs/domains/scoping/write-guard.md].

## Why the default scope alone is not enough

The default scope puts `tenant_id = <current>` on every relation, but an association's relation is built as `target_scope.merge!(association_scope)`, and Active Record's `WhereClause#merge` drops every predicate of the receiver on a column the other side constrains. The owner's `tenant_id = <owner>` therefore REPLACES the default scope's `tenant_id = <current>`, so `other_tenant.widgets` reads the other tenant's rows while the current tenant is something else. [DECISION:the read guard exists because of that replacement]; a plain `where` appends instead of replacing, which is why a test that only chains `where(tenant_id: other)` never shows the leak. The same replacement happens with `rewhere`, `merge` of an unscoped relation, `unscope`, and an `or` against another tenant's relation. [SPEC:spec/scoping/read_guard_spec.rb] ("reads through another tenant's association" and "relation surgery that drops or replaces the tenant filter") has one example per entry point.

### Gotcha: `other_tenant.widgets.destroy_all` deletes another tenant's rows

[SYMPTOM:acting in tenant B, `a.widgets.destroy_all` removes tenant A's rows and raises nothing]. [CAUSE:`CollectionProxy#destroy_all` loads the target and destroys each record; it never calls `Relation#destroy_all`, so the bulk-write guard does not run]. [FIX:the read guard refuses the load, so nothing is deleted]. Proof: [SPEC:spec/scoping/read_guard_spec.rb] ("a bulk destroy through another tenant's association") and the "tenant association" example in [SPEC:spec/security/red_team_spec.rb].

## Where it hooks

The guard is part of [MODULE:TenancyDable::RelationExtension], prepended to [CLASS:ActiveRecord::Relation] by the railtie (see [REF:boot.md]). Each hook runs [METHOD:tenancy_guard_read!] and then [METHOD:super], with `(...)` forwarding. The hooks, and what each one covers:

- [METHOD:exec_queries] (private) covers every record load: `to_a`, `first`, `find`, `find_by`, `find_each`, `in_batches`, preloads, association readers and a scheduled `load_async` once it is read.
- [METHOD:perform_calculation] (private) covers `count`, `size`, `sum`, `average`, `minimum`, `maximum`, grouped calculations and the `async_*` calculations.
- [METHOD:pluck] (public) covers `pluck`, `pick`, `async_pluck` and the `widget_ids` reader, whose implementation calls `scope.pluck`.
- [METHOD:exists?] (public) covers `exists?`, which runs `select_rows` itself, and through it `any?` / `empty?` / `none?` on an unloaded relation.
- [METHOD:ids] (public) covers `ids` and `async_ids`, which build their own select and skip the hooks above.
- [METHOD:load_async] (public) refuses the query before it is scheduled when an async executor is configured; without an executor it calls `load` and the guard simply runs twice.
- [METHOD:compute_cache_version] (public) covers `cache_version` and `cache_key_with_version` on an unloaded relation, which send their own `COUNT` / `MAX` query and would otherwise leak another tenant's row count and newest timestamp.
- [METHOD:arel] (public) covers a scoped relation compiled into a subquery, a `from` or a `with` of ANY model (including one that is not tenant-scoped), because such a relation is never loaded and every embedding is compiled through `arel`.

The private hooks are defined under `private` in the module so the prepend keeps them private; [SPEC:spec/contract_spec.rb] locks the override list, the visibility of the private pair, and that Active Record itself defines `compute_cache_version` and `arel` as public. Proof per hook is one example each in [SPEC:spec/scoping/read_guard_spec.rb]: the association-read list ("refuses to_a", "refuses find_each", "refuses ids", "refuses load_async" and the rest), "collection cache keys", "a scoped relation compiled into another model's query", and "load_async with an async executor", which stubs `async_enabled?` on the SQLite adapter to schedule real async queries.

[RULE:`to_sql` and `arel` of a refused relation raise too]. Hooking `arel` is what closes the subquery path, and it has the side effect that merely compiling a refused relation to SQL raises [ERROR:TenancyDable::CrossTenantReadError]. Proof: "refuses to_sql of a refused relation". The classifier reads `where_clause` and `unscope_values` and never `arel`, so the hook cannot recurse.

A scoped model's `find` and `find_by` never take Active Record's statement-cache path (the default scope makes the relation non-trivial), and an association reader skips the association statement cache for the same reason, so both reach [METHOD:exec_queries] and the hook sees them.

## The read decision tree

[METHOD:tenancy_guard_read!] returns without checking anything in four cases, in this order, and otherwise classifies the relation:

1. `config.guard_reads` is falsy. The setting is a boolean on and off, default on; its place is in [REF:configuration.md].
2. The relation's model is not tenant-scoped (it does not respond to [METHOD:tenant_scoped?] with true). Proof: [SPEC:spec/scoping/read_guard_spec.rb] ("leaves a model that is not tenant-scoped untouched").
3. [STATE:Current.tenant_scope_disabled] is true, that is, inside `without_tenant`. Proof: "allows a deliberate cross-tenant read inside without_tenant".
4. There is no current tenant. The default scope decides there: it raises `NoTenantError` when `require_tenant` is truthy and otherwise reads unfiltered. Proof: "passes a fail-open read with no current tenant and require_tenant off" and "leaves the decision to the default scope with no current tenant".

Otherwise [METHOD:tenancy_pin_state] answers one of four states. The guard raises [ERROR:TenancyDable::CrossTenantReadError] for [STATE:other] and [STATE:removed], and lets [STATE:current] and [STATE:unpinned] through.

## The pin classifier

[METHOD:tenancy_pin_state] takes the current tenant and returns [STATE:current], [STATE:other], [STATE:removed] or [STATE:unpinned]. Both guards call this one method, so what they reason about cannot drift. It first collects the tenant column's LITERAL pins and then applies these rules IN THIS ORDER; the first match wins.

1. [STATE:other] when any literal pin is another tenant, or is a list that holds any value that is neither nil nor the current id. A multi-tenant read such as `where(tenant_id: [current, other])` is therefore `:other` even though it contains the current id.
2. [STATE:current] when any literal pin is the current id, or is a list whose non-nil values are all the current id (`[current, current]`), or is an empty list. The conjunct confines the rows to the current tenant.
3. [STATE:removed] when the relation is a [MODULE:TenancyDable::BuiltWithoutTenant] (checked with `is_a?` and with `extending_values.include?`, because `extending_values` survives `dup` while `dup` drops the singleton extension).
4. [STATE:removed] when `unscope_values` records a removal of the column: `:where` as a whole, or a `{where: targets}` entry where a target names the tenant column. A target is a Symbol, String or Arel attribute, a list of them, or a table-keyed Hash (`{widgets: :tenant_id}`, `{"widgets" => ["tenant_id"]}`, also inside a list), flattened to column names first. A Symbol or String compares its last dot-separated segment, so `"widgets.tenant_id"` counts; an Arel attribute compares its `name`, which is how `rewhere` records its removal.
5. [STATE:removed] when ANY top-level predicate of the where clause other than an explicit nil pin references the tenant column of the relation's table: `!=`, `NOT`, a range, a subquery, an Arel equality against a non-literal, an `or` Grouping, whatever replaced the default scope's equality.
6. [STATE:unpinned] otherwise.

The order is deliberate. A pin to the current tenant (rule 2) wins over the marker and over a recorded removal (rules 3 and 4), so `rewhere(tenant_id: current)` and `unscope(where: :tenant_id).where(tenant_id: current)` read only the current tenant and pass, and a marked relation merged into a relation built in the current tenant is `:current`. A pin to the current tenant also wins over a non-literal equality beside it, which is what lets `Tenant.where(id: b).eager_load(:widgets)` through: its join scope is `tenant_id = B AND widgets.tenant_id = tenants.id`. A pin to another tenant (rule 1) wins over a pin to the current one. Proofs are in [SPEC:spec/scoping/read_guard_spec.rb]: "what passes" (rewhere and unscope-then-where of the current tenant), "a relation built with no tenant filter, loaded inside a tenant" (the marker, and the marked-relation-merged-into-current case), "table-keyed Hash unscope targets", and "non-equality predicates on the tenant filter".

### Literal pins

[RULE:the classifier reads literal pins from `where_clause.ast`, never from `where_values_hash`]. It walks the top-level conjunction of the where clause (recursing into `Arel::Nodes::And`), keeps the nodes whose `equality?` is true ([CLASS:Arel::Nodes::Equality], [CLASS:Arel::Nodes::In] and a [CLASS:Arel::Nodes::HomogeneousIn] of type `:in`), and keeps those whose left side is an [CLASS:Arel::Attributes::Attribute] named the tenant column on the relation's own table. The value is `right.value_before_type_cast`, or the list of those values for a list; the comparison against the current id is by string form. A right side that is not a bound value (a subquery, a column, an `Arel.sql` literal) yields no pin, and rule 5 then classifies the predicate as `:removed`. [SPEC:spec/scoping/read_guard_spec.rb] ("refuses an Arel equality on the fk against a subquery, through merge and unscoped" and "against a column or an Arel.sql literal") proves that, and "names the other tenant of a list pin in the message" proves the list reading.

A list is judged as one pin: `where(tenant_id: [current, current])` and `where(tenant_id: [])` read only the current tenant and pass ("reads where(tenant_id: [b, b]) and where(tenant_id: [])"), and a list that names another tenant is refused. Active Record builds the Hash spelling `where(tenant_id: [current, nil])` as `tenant_id IS NULL OR tenant_id = current`, an `or` Grouping, so the list rule never sees it. Beside the default scope's pin the relation is `:current` (rule 2) and reads only the current tenant; on an unscoped relation rule 5 classifies the Grouping as `:removed`. No committed example exercises a list that holds nil.

### The nil-pin exception

[RULE:an explicit nil pin is the one predicate on the tenant column that stays `:unpinned`]. `where(tenant_id: nil)` builds an `Equality` whose literal value is nil; it is neither another tenant nor the current one, and rule 5 exempts exactly that shape (a top-level `Arel::Nodes::Equality` on the column with a nil literal). The read passes, because a nil pin reads only rows that belong to no tenant and never another tenant's rows. Beside the default scope's own pin (`Widget.where(tenant_id: nil)`), rule 2 wins and the relation is `:current`. The exemption matters where nothing else pins the column: `unscoped.where(tenant_id: nil)` and an unsaved owner's association (`Tenant.new.widgets`, whose merge replaces the default scope's predicate with `tenant_id IS NULL` and adds `1=0`). Proof: [SPEC:spec/scoping/read_guard_spec.rb] ("keeps an explicit nil pin unpinned (not refused)"). The exemption is only for an Equality with a nil literal: a subquery on the column looks like a nil pin through `where_values_hash`, which is the second reason the classifier does not use that method.

### Gotcha: `where_values_hash` must never be called from a guard

[SYMPTOM:every read of a scoped model inside a tenant raises `NoMethodError: undefined method 'relation'` for an Arel function node, for example when a case-insensitive uniqueness validation runs]. [CAUSE:Active Record's `WhereClause#to_h`, which `where_values_hash` calls, reads `node.left.relation.name` on every top-level equality, and `lower(name) = ?` has a `NamedFunction` on the left; separately, `where_values_hash` keeps the last value per column, which hides a current-tenant pin behind a non-literal equality such as an `eager_load` join, and reports nil for a subquery]. [FIX:read the pins from `where_clause.ast` as above]. [RULE:no code in `relation_extension.rb` may call `where_values_hash` or `where_clause.to_h`]. Proof: [SPEC:spec/scoping/read_guard_spec.rb] "the classifier reads literal pins from the where clause" (a `lower(...)` equality via `validates ... case_sensitive: false`, via `validates_uniqueness_to_tenant`, and via `where(arel_table[:name].lower.eq(...))`). The upstream angle is in [REF:upstream.md].

### How the walk reads `or` on every Active Record line

The walk that finds a predicate mentioning the column is duck-typed because [CLASS:Arel::Nodes::Or] is a [CLASS:Arel::Nodes::Binary] on Active Record 7.1 (`left` / `right`) and an n-ary node on 7.2 and later (`children`). The walk matches an `Arel::Attributes::Attribute` by `name` and table name, recurses into a `HomogeneousIn` through its `attribute`, into arrays element by element, and into any other node through `children`, `left` / `right` and `expr` wherever the node responds to them. [SPEC:spec/scoping/read_guard_spec.rb] ("refuses an or with another tenant's association") runs on every Rails line of the CI matrix.

## What is refused and what passes

Inside `with_tenant(b)`, [SPEC:spec/scoping/read_guard_spec.rb] proves these are refused: every read through another tenant's association (the `widgets` list, a `has_one` reader, `widget_ids`); `rewhere(tenant_id: other)`; a `merge` of another tenant's unscoped relation; `unscope(where: :tenant_id)`, `unscope(where: "widgets.tenant_id")` and `unscope(:where)`; an `or` with another tenant's association; `where(tenant_id: other)` and a list across tenants; `unscoped.where(tenant_id: other)`; a preload of another tenant's owners; `invert_where` on a host scope or on the model; `unscoped.where.not(tenant_id: other)`; a merge that brings a range or a `where.not` on the column; a subquery on the column; a relation built with no tenant and loaded inside one; the cache key and version of a refused relation; and a refused relation compiled into a subquery, `from` or CTE. [RULE:code that pins another tenant is a bug whether it gets nothing or something back]; the fix is `with_tenant(other) { ... }` or a deliberate `without_tenant`.

What passes on purpose, each with an example in the same spec's "what passes" group: the current tenant's own association and its ids; a preload of the current tenant's owners; `Model.count` and the default scope's own reads; `rewhere(tenant_id: current)`; `unscope(where: :tenant_id).where(tenant_id: current)`; `unscope(where: :name)` (only the tenant column counts, because hosts legitimately unscope other columns); an association pinned on another column (`widget.children`, whose default scope stays); `eager_load` from the tenant side; `reload`; the gem's own `unscoped.where(id:).pick(:tenant_id)`; and everything inside `without_tenant`. [RULE:`Model.unscoped` with no tenant predicate must keep passing], because Active Record's `UniquenessValidator` builds on `klass.unscoped`, `reload` runs inside `unscoped { }`, and the cross-tenant `belongs_to` validation uses `unscoped.where(id:).pick(fk)`.

A relation built in one context and loaded in another is judged at load. [SPEC:spec/scoping/read_guard_spec.rb] ("a relation built with no tenant filter, loaded inside a tenant") refuses it inside another tenant, and allows it when loaded with no tenant, when loaded inside `without_tenant`, when built inside the current tenant, when pinned to the current tenant, and when a marked relation is merged into one pinned to the current tenant. "refuses stale.dup, which drops the singleton marker" proves the `extending_values` check; the spec builds that stale relation with `TenancyDable::Current.set(tenant: nil)`.

## The error

[ERROR:TenancyDable::CrossTenantReadError] descends from `TenancyDable::Error` and is a sibling of `BulkWriteError`; the hierarchy is in [REF:errors.md]. The message is "refusing to read <Model> " followed by "pinned to tenant <pin inspected>" for `:other` or "with the tenant filter removed" for `:removed` (which also covers the marker), then " while acting in tenant #<id>; enter the tenant with TenancyDable.with_tenant, or wrap a deliberate cross-tenant read in TenancyDable.without_tenant". [RULE:the message carries the model name and tenant ids only, never a record payload]. For a list pin the inspected value is the list. Proof: [SPEC:spec/scoping/read_guard_spec.rb] "the message" group, and the list case under "the classifier reads literal pins".

## The off switch

[CONFIG:guard_reads] defaults to true; `false` disables only this guard. The bulk-write guard, the foreign-tenant refusal and the insert guard stay on, and [SPEC:spec/scoping/read_guard_spec.rb] ("does not affect the bulk-write guard") proves the first of those. With the guard off, the association leak returns the other tenant's rows and an explicit `where(tenant_id: other)` returns an empty set.

## Documented residuals

The guard targets the shapes Active Record produces on its own (association merge, `rewhere`, `merge`, `unscope`, `or`). A relation whose where clause no longer mentions the tenant column and that recorded no removal is indistinguishable from `Model.unscoped`, and passes. These residuals are accepted:

- [RESIDUAL:Model.unscoped with no tenant predicate, and `unscoped { }`]. Proof of the unmarked relation: "does not mark Model.unscoped (documented residual)".
- [RESIDUAL:`except(:where)` and `only(...)` without `:where`], which drop the predicate without recording a removal.
- [RESIDUAL:an `or` with an unscoped relation, or with a stale one]. `Widget.all.or(Widget.unscope(where: :tenant_id))` collapses to no predicate. `Widget.where.not(name: nil).or(stale)`, where `stale` was built before the tenant was entered, loses the tenant pin because Active Record's `WhereClause#or` keeps only the predicates both sides share, and `or!` does not carry the marker. An `or` with another tenant's association is NOT a residual; it is refused.
- [RESIDUAL:SQL-string predicates], such as `where("tenant_id = ?", x)`, which are opaque strings the classifier cannot read.
- [RESIDUAL:raw SQL strings], such as `find_by_sql` and `connection.select_all` with a String. A relation passed to `select_all` is compiled through `arel` and refused.
- [RESIDUAL:`reload` by id], which runs inside `unscoped { }` and reads the row the record already is. Proof: "allows reload".
- [RESIDUAL:the cache key of an already-loaded association target], because no query runs and it reads records already in memory.

Only the unmarked `Model.unscoped` and `reload` have examples that assert the pass-through; the other residuals follow from the classifier rules above and are listed in the README.

## Gotchas specific to this guard

### Gotcha: A nil pin is not a tenant pin

[SYMPTOM:an unsaved owner's association (`Tenant.new.widgets`) is not refused]. [CAUSE:the owner's id is nil, so the association's `tenant_id IS NULL` replaces the default scope's predicate and the classifier keeps it `:unpinned`; the nil pin reads only rows with no tenant, and Active Record adds `1=0` for an unsaved owner]. [RULE:never read `:unpinned` as proof that a relation is confined to a tenant].

### Gotcha: A spec that builds a relation under a different context uses `Current.set`

[SYMPTOM:a test needs a stale relation or one built inside another tenant]. [CAUSE:`Current.set` is raw state and skips the facade (see [REF:context.md]), which is exactly what a test of the guard wants]. [FIX:build it inside `TenancyDable::Current.set(tenant: nil) { ... }` or `TenancyDable.with_tenant(...)`, then load it elsewhere]. [RULE:application code never writes `Current` directly].

## Related

The bulk-write guard and the write refusals that share the classifier are in [SPOKE:docs/domains/scoping/write-guard.md]; the declarations that mark a model scoped are in [REF:declarations.md]; Active Record's `where_values_hash` raising on a function-left equality is the first row of [REF:upstream.md].
