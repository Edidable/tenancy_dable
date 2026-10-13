# Scoping: the declaration and the default scope

> Part of the [scoping domain](../scoping.md).

This spoke covers what [MACRO:belongs_to_tenant] installs on a model, the default scope that filters every read to the current tenant, the marker that tags a relation built without a tenant, the immutability of the tenant column, and the two validations a scoped model carries. The code is [FILE:lib/tenancy_dable/scoped.rb]; the contract is frozen in `DESIGN.md` §5.1 and amended in §16.1 and §16.2.

## What the macro installs

A host model gains the macro by `include TenancyDable::Scoped`, an [CLASS:ActiveSupport::Concern] defined in [FILE:lib/tenancy_dable/scoped.rb]. [MACRO:belongs_to_tenant] takes an association name (default [ARG:tenant]), a [ARG:tag:] and any [CLASS:belongs_to] options, and installs these steps in this order:

1. The tenancy declaration through [METHOD:tenancy_declare!], which raises before anything else is installed when the model already declared itself; the single-declaration rule is in [REF:declarations.md].
2. The [CLASS:belongs_to] association, with the options the host passed.
3. The class predicate [METHOD:tenant_scoped?], defined only on classes that called the macro, so `respond_to?(:tenant_scoped?)` is the discriminator the guards and the cross-tenant validation use to tell a scoped model from any other.
4. The default scope (below).
5. Three callbacks that refuse a write into another tenant: [CALLBACK:before_validation], [CALLBACK:before_save] and [CALLBACK:before_destroy], all declared with `prepend: true` (detailed in [SPOKE:docs/domains/scoping/write-guard.md]).
6. The auto-assign of the tenant column on create.
7. The immutability writer and its [CALLBACK:before_update] backstop.
8. The cross-tenant [CLASS:belongs_to] validation.

Everything contextual is read at query time from [CLASS:TenancyDable::Current] and the configuration: the current tenant, the bypass flag, whether `require_tenant` is truthy. Everything structural is captured once when the model declares itself: the tenant column name is [CONFIG:tenant_fk] read at declaration, and the association is the one the macro built.

### Gotcha: The tenant column is bound at declaration

[SYMPTOM:after [CONFIG:tenant_fk] is changed once scoped models have loaded, the default scope filters one column while the guards and some overrides check another]. [CAUSE:the default scope, the auto-assign, the writer, the validation, the uniqueness helper's scope and the foreign-tenant refusal callbacks use the column that [CONFIG:tenant_fk] named when the macro ran, while the guards in [FILE:lib/tenancy_dable/relation_extension.rb] and the `touch`, `update_columns` and `delete` overrides read [CONFIG:tenant_fk] on every call]. [FIX:set `tenant_fk` in the initializer, before any scoped model is loaded]. [RULE:never change `tenant_fk` after a scoped model has loaded].

## The default scope decision tree

The default scope is a fixed decision tree evaluated when a relation is built; [SPEC:spec/scoping/default_scope_spec.rb] pins one example per branch.

- When [STATE:Current.tenant_scope_disabled] is true (inside `without_tenant`), the scope applies no filter and returns the relation extended with [MODULE:TenancyDable::BuiltWithoutTenant]. Proof: "disables scoping inside without_tenant and restores it after the block".
- Otherwise, when a current tenant exists, the scope is `where(tenant_fk => current_tenant.id)`. The filter is a plain `where`, applied before any ordering the caller adds, so an `order` or a `limit` can never run against an unfiltered set. Proof: "filters reads to the current tenant and excludes other tenants' rows".
- Otherwise, when `require_tenant` is truthy in context, the scope raises [ERROR:TenancyDable::NoTenantError] with the message "<Model> was queried with no current tenant while require_tenant is active". This is the fail-closed branch. Proof: "raises NoTenantError when require_tenant is truthy and no tenant is set (fail-closed)".
- Otherwise the scope applies no filter and returns the relation extended with the marker. This is the fail-open default, and it is what [CONFIG:require_tenant] set to `false` selects. Proof: "returns every row when require_tenant is falsy and no tenant is set (fail-open)".

"Truthy in context" is [METHOD:TenancyDable::Scoped.require_tenant_in_context?]: a callable setting is invoked and its result tested, a plain value is tested directly. [SPEC:spec/scoping/default_scope_spec.rb] proves the callable form ("treats a callable require_tenant as truthy-in-context") and the bypass inside `without_tenant` even when `require_tenant` is truthy. The setting itself and its validation are in [REF:configuration.md]; the bypass and the facade that sets the current tenant are in [REF:context.md].

### Gotcha: A fail-closed model raises even on `Model.new`

[SYMPTOM:with `require_tenant` truthy and no current tenant, `Widget.new` raises `NoTenantError` before any query runs]. [CAUSE:Active Record evaluates the default scope to compute the attributes of a new record, so the fail-closed branch fires on construction]. [FIX:build fixtures and factories before arming `require_tenant` in a spec, or inside `with_tenant`]. [RULE:a fail-closed host must enter a tenant before it instantiates a scoped model]. The specs build rows first and arm the setting after, as the comments in [SPEC:spec/scoping/default_scope_spec.rb] and [SPEC:spec/security/red_team_spec.rb] record.

## The built-without-tenant marker

[MODULE:TenancyDable::BuiltWithoutTenant] is an empty module, defined in [FILE:lib/tenancy_dable/relation_extension.rb]. The default scope extends a relation with it on exactly the two branches that apply no tenant filter: the `without_tenant` bypass and the fail-open default. [SPEC:spec/contract_spec.rb] locks the module's emptiness and the fail-open marker (`Widget.all` built with no tenant is a `BuiltWithoutTenant`, and `Widget.all` built inside `with_tenant` is not); the bypass branch is proved by [SPEC:spec/scoping/read_guard_spec.rb] ("refuses a relation built inside without_tenant").

The marker exists because the default scope is evaluated when a relation is BUILT, not when it loads. A relation built with no tenant (`relation = Widget.order(:id)` before any `with_tenant`) carries no tenant predicate, and loading it later inside a tenant would read every tenant, indistinguishable from `Model.unscoped`. The marker makes the read guard classify that relation as having lost its tenant filter and refuse it; how the classifier reads the marker is in [SPOKE:docs/domains/scoping/read-guard.md].

[ABSENCE:Model.unscoped is never marked]. `unscoped` is Active Record's own explicit bypass and the gem keeps it working, so a relation from `Widget.unscoped` with no tenant predicate is a documented residual of the read guard, not a marked relation. [SPEC:spec/scoping/read_guard_spec.rb] ("does not mark Model.unscoped (documented residual)") proves it.

## The tenant column on create

A record built inside a tenant already carries the current tenant's id: Active Record copies the default scope's `where` into a new record's attributes. [RULE:a blank tenant column is filled from the current tenant on create], which covers a record built outside any tenant and saved inside one. A [CALLBACK:before_validation] with `on: :create` assigns `current_tenant.id` when the column is blank and a tenant is current. It writes through `self[fk] =`, which skips the immutability writer (the record is not persisted, so the writer would not fire anyway). Proof: [SPEC:spec/scoping/tenant_assignment_spec.rb] ("assigns tenant_id from the current tenant when left blank"). With no current tenant the column stays blank ("leaves tenant_id blank when there is no current tenant (fail-open create)").

A non-blank column that names another tenant is not overwritten: the foreign-tenant refusal in [SPOKE:docs/domains/scoping/write-guard.md] raises first. An explicit column equal to the current tenant, and any column when there is no current tenant, persist unchanged.

### Gotcha: `save(validate: false)` skips the auto-assign

[SYMPTOM:a record built with no current tenant (or with the column set to nil), then saved with `validate: false` inside a tenant, keeps a blank tenant column]. [CAUSE:the auto-assign is a validation callback, and `validate: false` skips validation callbacks; the foreign-tenant refusal treats a blank column as "the auto-assign decides" and lets it pass; a record built inside the tenant is not affected, because it already holds the id from the default scope]. [FIX:assign the tenant explicitly (`tenant:` or the column) when saving without validation]. No example asserts this path; it follows from the callback order in [FILE:lib/tenancy_dable/scoped.rb].

## Immutability of the tenant column

[RULE:a persisted record's tenant never changes]. Three paths enforce it, each raising [ERROR:TenancyDable::TenantImmutableError] with the message "<Model>#<fk> is immutable; a record's tenant cannot change after create".

- The column writer ([METHOD:tenant_id=] or whatever [CONFIG:tenant_fk] names) raises when the record is persisted, holds a non-nil value and is given a value whose string form differs. Assigning the same value is a no-op, and a new record may take any value. Proof: [SPEC:spec/scoping/tenant_assignment_spec.rb] ("raises TenantImmutableError when the fk writer reassigns a persisted record", "allows reassigning the SAME tenant_id to a persisted record (no-op)", "allows setting tenant_id on a new, unpersisted record").
- A [CALLBACK:before_update] backstop raises when the column has an unsaved change. It exists for the association writer: `record.tenant = other` sets the column through `write_attribute` and slips past the writer override. Proof: "raises TenantImmutableError when the tenant association is reassigned on save"; mass assignment through `update!(tenant_id: x)` is covered by [SPEC:spec/security/red_team_spec.rb] ("refuses every reassignment path on a persisted record").
- The callback-free and bulk writes, [METHOD:update_columns], [METHOD:update_column] and the Hash form of [METHOD:update_all], refuse a rewrite of the column too; they are covered in [SPOKE:docs/domains/scoping/write-guard.md].

## Cross-tenant `belongs_to` validation

A scoped model validates that every [CLASS:belongs_to] association pointing at another scoped model references a record in the SAME tenant. The validation skips the tenant association itself, polymorphic associations, associations whose class cannot be resolved ([ERROR:NameError] is rescued), targets that are not tenant-scoped, a record with a nil tenant column, and a nil foreign key. For each remaining reflection it reads the target's tenant with `assoc_klass.unscoped.where(id: assoc_id).pick(fk)`, deliberately `unscoped`, because the default scope would hide a foreign-tenant row and mask the breach. A mismatch adds the error key [KEY:cross_tenant] to the association name; its text is the `errors.messages.cross_tenant` locale entry ([REF:i18n.md]), whose English default equals the compatibility constant [CONST:TenancyDable::CrossTenantError::MESSAGE].

It ADDS an error and does not raise, because the input (a parent id) plausibly comes from a form. Proof: [SPEC:spec/scoping/cross_tenant_spec.rb] covers a same-tenant target (valid), a foreign target (invalid with "belongs to a different tenant"), the breach found while another tenant is current, and a message equal to the English default `CrossTenantError::MESSAGE`; [SPEC:spec/security/red_team_spec.rb] repeats the attack.

[RESIDUAL:the validation is an id-existence oracle across tenants]. A foreign parent id adds the error while a nonexistent id adds nothing, so a user who controls the parent id can learn which ids exist in other tenants, and a dangling parent id is saved without an error. The gem accepts this; a host that exposes a parent id to untrusted input validates the id against its own scoped lookup first.

The validation reads `unscoped.where(id:)` with no tenant predicate, which the read guard classifies as unpinned and lets through. [SPEC:spec/scoping/read_guard_spec.rb] ("allows unscoped.where(id:).pick(:tenant_id), the gem's own lookup") proves the guard leaves it alone.

## Per-tenant uniqueness

[METHOD:validates_uniqueness_to_tenant] takes attribute names and options, removes the caller's `:scope`, and calls `validates_uniqueness_of` with the scope `[fk] + caller_scope` (deduplicated). A name is unique within a tenant and may repeat across tenants. Proof: [SPEC:spec/scoping/uniqueness_spec.rb]. The fixture schema keeps its index non-unique so the validation is the system under test.

A case-insensitive uniqueness validation builds a `lower(column) = lower(?)` predicate, an equality whose left side is a function. The read guard must classify the relation that validation reads without erroring; [SPEC:spec/scoping/read_guard_spec.rb] ("reads a scoped model with a case-insensitive uniqueness validation inside its tenant" and "validates_uniqueness_to_tenant with case_sensitive: false saves inside its tenant") proves both the plain validator and this helper save inside their tenant. The reason is in [SPOKE:docs/domains/scoping/read-guard.md].

### Gotcha: A global uniqueness validation reveals other tenants' values

[SYMPTOM:`validates :code, uniqueness: true` on a scoped model rejects a value that only ANOTHER tenant holds]. [CAUSE:Active Record builds the uniqueness query on `klass.unscoped`, which drops the default scope, so the check sees every tenant]. [FIX:use `validates_uniqueness_to_tenant`]. The read guard deliberately lets this pass, because `unscoped` with no tenant predicate is the explicit bypass Active Record itself relies on; the choice of a global constraint is the host's.

## Known limit: counters and `increment!`

### Gotcha: Counters and `increment!` raise `BulkWriteError`

[SYMPTOM:`record.increment!(:count)`, or creating a child whose `belongs_to` has `counter_cache: true` onto a scoped parent, raises `TenancyDable::BulkWriteError` on a scoped model, both while the record's own tenant is current and with no current tenant]. [CAUSE:Active Record builds the counter update on `unscoped.where(id:)`, a relation with no tenant pin, and the bulk-write guard accepts only a relation pinned to the current tenant]. [FIX:`increment` plus `save`, or wrap the counter update in `TenancyDable.without_tenant(reason:)`]. [RULE:do not weaken the bulk-write guard to accept an unpinned relation to make counters work]. No example in `spec/` asserts the counter case; the guard rule that causes it is proved in [SPEC:spec/security/red_team_spec.rb] ("escape attempt via `unscoped`" is refused inside a tenant).

## Related

The read and write guards that sit on top of the default scope are [SPOKE:docs/domains/scoping/read-guard.md] and [SPOKE:docs/domains/scoping/write-guard.md]; the errors are listed in [REF:errors.md].
