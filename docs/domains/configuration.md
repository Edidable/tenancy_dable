# Configuration

## Overview

The host configures the gem once, in an initializer, through [METHOD:TenancyDable.configure]. The settings object is [CLASS:TenancyDable::Configuration] in [FILE:lib/tenancy_dable/configuration.rb]; the settings and their defaults are frozen by the contract (`DESIGN.md` §4.1 and §16.7). [SPEC:spec/contract_spec.rb] "configuration settings + frozen defaults" asserts each default and derives the set of settings from the class's own writers, so adding or removing a setting without updating that spec fails loudly.

## The API

[METHOD:TenancyDable.configure] yields the configuration to the host's block, then calls `validate!` on it and returns the configuration. Without a block it only returns the configuration. A block that leaves an invalid value raises [ERROR:ConfigurationError] at boot, before any request.

[METHOD:TenancyDable.configuration] answers the memoized settings object. [METHOD:TenancyDable.reset_configuration!] replaces it with a fresh default object; the suite calls it after every example ([SPEC:spec/rails_helper.rb]), so a spec that changes a setting never leaks it. `validate!` returns the configuration itself so a call can chain ([SPEC:spec/configuration_spec.rb] "returns self on success").

[RULE:configuration is validated in validate!] Whatever a setting must satisfy is checked in `Configuration#validate!` and nowhere else; a consumer may assume the value is valid when it came through `configure`. Settings assigned directly on the object after `configure` are not re-validated.

The resolver helpers `tenant_class`, `user_class` and `membership_class` constantize the model names lazily, so the host's models need not be loaded when the gem is configured; `role?` and `manager_role?` test a name against the configured lists.

## The settings

Each setting is listed with its default, the rule `validate!` applies to it (none when it is unchecked), and where it is consumed. The spec that proves a default is [SPEC:spec/contract_spec.rb]; the spec that proves a `validate!` rule is [SPEC:spec/configuration_spec.rb] unless another is named.

### Models and roles

[CONFIG:tenant_model] defaults to `"Tenant"`, [CONFIG:user_model] to `"User"` and [CONFIG:membership_model] to `"Membership"`. `validate!` rejects a nil or blank name. The identity concerns and resolution read them to find the classes.

[CONFIG:roles] defaults to `%w[owner admin member]`, ordered highest first. `validate!` rejects an empty list. The first role is the owner role: it drives `Membership.owners`, `Tenant#owners`, the last-owner guard and `Policy::Base#owner?`, and one predicate per role is generated from the list ([REF:identity.md]).

[CONFIG:manager_roles] defaults to `%w[owner admin]`. `validate!` rejects any entry that is not in `roles`. It drives `Membership.admins`, `Membership#manager?` and `Policy::Base#manager?`.

### Names

[CONFIG:tenant_fk] defaults to `:tenant_id` and names the foreign key on tenant-scoped models. It is read when `belongs_to_tenant` runs, so it is fixed per model at declaration time. It is not validated. The audit also uses it to find the column and the index ([REF:declarations.md]). The scoping engine, the guards, `Policy::Base::Scope` and the audit honour the configured column; the membership uniqueness and last-owner queries, `User#membership_for`, `TenancyDable.current_membership` and `Policy::Base#same_tenant?` read the literal `tenant_id`, and the model generator honours a custom column in its migration only ([REF:identity.md], [REF:generators.md]).

[CONFIG:slug_param] defaults to `:tenant_slug` and names the URL parameter that resolution and the opt-in Cable concern read. It is not validated.

### Isolation behavior

[CONFIG:require_tenant] defaults to `false`: a scoped query with no current tenant fails open and returns the relation marked as built without a tenant. A truthy value makes the default scope raise `NoTenantError`; a callable is invoked when a scoped relation is built with no tenant and no bypass, and its result tested, so the mode can depend on context. Not validated. Proven by [SPEC:spec/scoping/default_scope_spec.rb].

[CONFIG:guard_reads] defaults to `true`. `validate!` requires `true` or `false`. When false, the read guard is off and a scoped read pinned to another tenant is no longer refused ([SPEC:spec/scoping/read_guard_spec.rb]).

[CONFIG:audit_overrides] defaults to `:log` and selects what happens when `current_tenant=` switches between two different tenants: `:log` writes a warning with tenant ids only, `:raise` raises `TenantOverrideError`, `:ignore` does nothing. Not validated: any other value behaves like `:log`.

[CONFIG:isolation_check] defaults to `:raise`. `validate!` requires `:raise`, `:warn` or `:off`. It governs what a gem write to `Current` does under a fiber scheduler with thread isolation ([REF:context.md]; [SPEC:spec/facade/isolation_check_spec.rb]).

[CONFIG:require_bypass_reason] defaults to `false`. `validate!` requires `true` or `false`. When true, `without_tenant` without a non-blank `reason:` raises `BypassReasonError` ([SPEC:spec/facade/without_tenant_audit_spec.rb]).

[CONFIG:rls] defaults to `false`, and [CONFIG:rls_statement] defaults to a callable that builds `SET app.tenant_id = <quoted id>`. When `rls` is on and the effective tenant id changes, the statement is executed on the Active Record connection; a nil statement is skipped. Neither is validated. Proven by [SPEC:spec/scoping/rls_spec.rb] and [SPEC:spec/integration/rls_toggle_spec.rb].

### Resolution

[CONFIG:on_tenant_not_found] defaults to `:raise`: an unknown slug raises `ActiveRecord::RecordNotFound`. `:null` publishes a cleared context and continues without a workspace. Not validated; a value other than `:null` behaves as `:raise` ([SPEC:spec/resolution/tenant_not_found_spec.rb]).

[CONFIG:on_not_a_member] defaults to `:not_a_member_error`, which raises `NotAMemberError`. `:not_authorized` raises `Pundit::NotAuthorizedError`, requiring Pundit lazily. A callable runs in the controller with the resolved tenant as its only argument. `validate!` rejects a Symbol outside the two known modes and checks nothing else: a non-callable non-Symbol passes validation and raises `TypeError` when resolution runs it ([SPEC:spec/resolution/not_a_member_behavior_spec.rb]).

[CONFIG:current_user_resolver] defaults to a callable that reads the host's top-level `::Current.user` when it exists and otherwise answers nil. It is run in the controller. Not validated.

### Audit

[CONFIG:audit_ignored_namespaces] defaults to a new, unfrozen Array per configuration: `ActiveStorage`, `ActionText`, `ActionMailbox`, `SolidQueue`, `SolidCache` and `SolidCable`. `validate!` requires an Array whose entries are non-blank Strings or Symbols. A host can add to it with `+=`.

[CONFIG:audit_allowed] defaults to an empty Hash mapping a model name to the reason a reviewed model is left out of the audit. `validate!` requires a Hash of non-blank String names to non-blank String reasons.

Both audit settings feed the skip rules in [REF:declarations.md]; the default value and the unfrozen, per-instance Array are proven in [SPEC:spec/contract_spec.rb].

## Adding a setting

If you add a setting, also update, in the same change:

1. [FILE:lib/tenancy_dable/configuration.rb]: the `attr_accessor`, the default in `initialize`, and the rule in `validate!` (or the reason it has none).
2. [FILE:spec/contract_spec.rb]: the default table and the writer-count assertion that locks the surface.
3. [FILE:spec/configuration_spec.rb]: one accepted and one rejected value when `validate!` checks it.
4. The settings table in [FILE:README.md].
5. The generator's commented initializer, [FILE:lib/generators/tenancy_dable/install/templates/initializer.rb.tt], with the default and the valid values.
6. The setting counts and the settings list in [FILE:DESIGN.md] (the §4.1 table and the delta that lists settings).
7. `CHANGELOG.md`, and `UPGRADING.md` if the default changes behavior for existing hosts.
8. This file and [FILE:.claude/rules/configuration.md].

## Gotchas

### Gotcha: A setting changed after the models load

[SYMPTOM:changing `roles`, `tenant_fk` or a model-name setting in a spec or a late initializer leaves some behavior on the old value]. [CAUSE:role predicates are defined, and the identity associations read `tenant_model`, `user_model` and `membership_model`, when the identity concerns are included, and the tenant column is bound when `belongs_to_tenant` runs, while `tenant_class` and `membership_class`, validations, scopes and guards read the configuration at call time]. [FIX:configure in an initializer, which runs before the host's models load]. [RULE:`tenant_fk` is bound when `belongs_to_tenant` runs; the role predicates and the identity associations' class names (`tenant_model`, `user_model`, `membership_model`) when the identity concerns are included; every other setting is read per call].

### Gotcha: `configure` validates, assignment does not

[SYMPTOM:`TenancyDable.configuration.isolation_check = :bogus` raises nothing]. [CAUSE:`validate!` runs only at the end of a `configure` block]. [FIX:set values inside `configure`]. [RULE:set through `configure`, never by assigning on the object].

## Related

The error `validate!` raises: [REF:errors.md]. Consumers: [REF:scoping.md], [REF:context.md], [REF:resolution.md], [REF:identity.md], [REF:declarations.md]. The generated initializer: [REF:generators.md].
