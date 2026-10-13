# Declarations and the audit

## Overview

Every Active Record model in a host is either tenant-scoped or global, and the gem makes the host say which. [FILE:lib/tenancy_dable/declarations.rb] holds the macro and the readers, [FILE:lib/tenancy_dable/audit.rb] holds the check that proves no model was forgotten, and [FILE:lib/tenancy_dable/tasks/audit.rake] exposes that check as a rake task. The contract is frozen in `DESIGN.md` §16.3.

The audit reads only class metadata and the schema: it never reads a row, and it never raises for a finding. A finding is a value the caller decides what to do with.

## The declaration

[CLASS:TenancyDable::Declaration] is a frozen `Data.define(:kind, :reason, :tag, :allow_tenant_fk)` value object. The [FIELD:kind] is `:scoped` or `:global`; the [FIELD:reason] is a String for a global model and nil for a scoped one; the [FIELD:tag] is a free-form Symbol, String or nil that a host builds its own grouping on; the [FIELD:allow_tenant_fk] flag is always false for a scoped model.

The module [CLASS:TenancyDable::Declarations] is extended onto `ActiveRecord::Base` by the railtie, so every Active Record class has the macro and the readers without including anything. `Scoped` stays a separate, explicit include that adds `belongs_to_tenant`.

[METHOD:tenant_global(because:, tag: nil, allow_tenant_fk: false)] declares a model global by decision. The `because:` reason is required and must be a non-blank String; the reason is duplicated and frozen, so the caller's string is never aliased ([SPEC:spec/declarations/declarations_spec.rb] "does not alias the caller's reason string").

[METHOD:belongs_to_tenant(name = :tenant, tag: nil, **opts)] declares a model scoped. The `tag:` goes to the declaration and is never forwarded to `belongs_to`; the declaration is made before anything is installed, so a refused declaration leaves the model with no association, no scope and no callbacks ([SPEC:spec/declarations/declarations_spec.rb] "raises on a second belongs_to_tenant before installing anything" and "refuses a bad tag before belongs_to runs").

Both macros end in one private writer, `tenancy_declare!`, which runs every check before it stores anything, in this order: the reason, then the tag, then the `allow_tenant_fk` flag, then the existing declaration. [SPEC:spec/declarations/declarations_spec.rb] "checks the reason before the tag and the tag before the flag" proves the order.

## The readers

[METHOD:tenancy_declaration] answers the class's own declaration, else its superclass's, else nil. [METHOD:tenancy_global_reason] and [METHOD:tenancy_tag] read from it and answer nil on an undeclared model and on `ActiveRecord::Base` ([SPEC:spec/declarations/declarations_spec.rb] "the readers"). [METHOD:tenant_scoped?] exists only on classes that called `belongs_to_tenant`; guards use `respond_to?(:tenant_scoped?)` as the discriminator.

## One declaration per lineage

A model declares once. A subclass inherits its parent's declaration through `tenancy_declaration`, so any declaration on a subclass of a declared class is refused, including a weaker one ([SPEC:spec/declarations/declarations_spec.rb] "refuses any declaration on a subclass of a declared class"). This holds for an abstract base that declares global as a blanket: the models below it inherit the declaration and cannot redeclare ([SPEC:spec/declarations/declarations_spec.rb] "refuses tenant_global on a base class below which models declare themselves"). A declaration on one class never reaches a sibling.

The reason a declaration cannot change is that a model that could be talked from scoped to global, or the reverse, after its class loaded would make the audit a snapshot of nothing. A second declaration, in either order, raises [ERROR:ConfigurationError] with the model name and the existing kind in the message ([SPEC:spec/declarations/declarations_spec.rb] "no re-declaration").

A bad declaration raises [ERROR:ConfigurationError] because it is a class-load misconfiguration, like an invalid setting. The messages name the model, or "an anonymous model" for a class with no name.

## The identity concerns declare themselves

`TenantModel`, `UserModel` and `MembershipModel` each call `tenant_global` when included, so a host never writes a declaration line for them. `Tenant` is global because it is the tenancy boundary itself; `User` is global because it spans tenants; `Membership` is global and passes `allow_tenant_fk: true` because it carries a tenant column and is read before any tenant is current ([SPEC:spec/declarations/declarations_spec.rb] "the identity concerns"). A host model that includes one of them cannot declare again.

The railtie extends `Declarations` onto `ActiveRecord::Base` before the identity concerns load, since they call the macro at include time ([FILE:lib/tenancy_dable/railtie.rb]).

## The audit

[METHOD:TenancyDable.audit(models = nil)] delegates to [METHOD:TenancyDable::Audit.run]. It answers a frozen Array of [CLASS:TenancyDable::Audit::Finding], each a `Data.define(:model, :kind, :message)` whose `to_s` is `"<model name>: <message>"`. The result is sorted by model name, then by the order of `Audit::KINDS` ([SPEC:spec/declarations/audit_spec.rb] "ordering").

With no argument the audit eager-loads the host application and audits every loaded, named model. With explicit models, as one class or an Array, it audits exactly those: no eager load and no name filter ([SPEC:spec/declarations/audit_spec.rb] "explicit models").

### Finding kinds

The kinds are listed in `Audit::KINDS`, and the audit spec proves each.

[ERROR:undeclared] means the model declares no tenancy. The message names the fix: `belongs_to_tenant`, or `tenant_global` with a reason. A model whose table does not exist is still checked ([SPEC:spec/declarations/audit_spec.rb] ":undeclared").

[ERROR:global_with_tenant_fk] means a model declared global has the configured tenant column. It is excused only by `allow_tenant_fk: true`, with one exception: a global model that shares its table with a tenant-scoped model is always flagged, because a scoped model reads the same rows and no flag can make that safe. The scoped-table set is built from the audited models plus every live model, so a global twin is caught even when the scoped model is not among the audited ones ([SPEC:spec/declarations/audit_spec.rb] ":global_with_tenant_fk"). The column name follows `config.tenant_fk`.

[ERROR:scoped_without_index] means a scoped model's table has no index whose first column is the tenant column. A single-column index counts, a composite index counts when the tenant column leads, and a composite primary key counts when the tenant column leads; an index where the column is not first does not count ([SPEC:spec/declarations/audit_spec.rb] ":scoped_without_index").

### What the audit skips

A model is skipped when it is abstract; when it is a real STI subclass, meaning its table is its base class's table, because the base class answers for the table; when its name equals or is namespaced under an entry of `config.audit_ignored_namespaces`; or when its name is a key of `config.audit_allowed`. A subclass that points at a different table is its own model and is audited. In the no-argument form, anonymous classes and stale descendants, whose constant was removed or reloaded, are dropped ([SPEC:spec/declarations/audit_spec.rb] "what is skipped").

The settings that steer these skips are documented in [REF:configuration.md].

## The rake task

[METHOD:rake tenancy_dable:audit] runs `TenancyDable.audit` in the `:environment` task. With findings it aborts with one finding per line on stderr, so the exit status is 1; with none it prints one line to stdout and exits 0. The railtie loads the task through its `rake_tasks` hook ([FILE:lib/tenancy_dable/railtie.rb]). [SPEC:spec/declarations/audit_task_spec.rb] proves both outcomes and that the task can be invoked again after `reenable`.

## Gotchas

### Gotcha: An undeclared model is not a safe model

[SYMPTOM:a model with no declaration and no tenant column reads and writes like any Active Record class, and nothing complains]. [CAUSE:the audit is opt-in tooling, run by the rake task or by a spec in the host, and `Declarations` never raises at class load for a model that declares nothing]. [FIX:run `rake tenancy_dable:audit` in CI, or assert `TenancyDable.audit` is empty in a host spec]. [RULE:the declaration is only as strong as the audit that runs against it].

### Gotcha: A global model on a scoped table is always flagged

[SYMPTOM:`allow_tenant_fk: true` does not silence a `global_with_tenant_fk` finding]. [CAUSE:the model shares its table with a tenant-scoped model, so the global declaration would read rows the scoped model protects]. [FIX:give the table one declaration, or split the table]. [RULE:`allow_tenant_fk` excuses a tenant column only on a table no scoped model uses].

### Gotcha: A global base class silences the audit below it

[SYMPTOM:`TenancyDable.audit` is clean although models were never declared]. [CAUSE:`tenant_global` on an abstract base is inherited through `tenancy_declaration`, so no model below it is `:undeclared`; the gem refuses only the declarations made below such a base, not the base declaration itself]. [FIX:declare each model, never a base class]. [RULE:a base class never declares tenancy].

## Related

Scoped models and their guards: [REF:scoping.md]. Settings the audit reads: [REF:configuration.md]. The identity concerns that declare themselves: [REF:identity.md]. The error all declaration failures raise: [REF:errors.md].
