# Errors

## Overview

Every error the gem raises descends from [CLASS:TenancyDable::Error], itself a `StandardError`, so a host can `rescue TenancyDable::Error` to trap any tenancy failure with one clause. The classes live in [FILE:lib/tenancy_dable/errors.rb], a file with no dependencies that the entry file loads before every other unit, so every other unit can reference them. [SPEC:spec/contract_spec.rb] "Error hierarchy" locks the list of names and asserts each is below `TenancyDable::Error`; the names are part of the public surface and are raised by name.

The guards raise rather than add validation errors wherever the input is a programming input and not user input. The one exception is the cross-tenant `belongs_to` check, which is a validation message because the associated id can come from a form.

## What raises each error

[ERROR:NoTenantError] is the fail-closed refusal. The default scope of a scoped model raises it when a query runs with no current tenant and `config.require_tenant` is truthy in context. The message names the model and carries no row data. Raised in [FILE:lib/tenancy_dable/scoped.rb]; proven by [SPEC:spec/scoping/default_scope_spec.rb].

[ERROR:TenantImmutableError] is raised when something tries to change the tenant column of a persisted scoped record: the attribute writer (`record.tenant_id = x`, mass assignment, `update(tenant_id: x)`), a `before_update` backstop for the association writer (`record.tenant = other`), `update_columns` and `update_column` with a different id, and `update_all` given a Hash that names the tenant column. A new record may still receive its tenant. Raised in [FILE:lib/tenancy_dable/scoped.rb] and [FILE:lib/tenancy_dable/relation_extension.rb]; proven by [SPEC:spec/scoping/tenant_assignment_spec.rb], [SPEC:spec/scoping/foreign_record_write_spec.rb] and [SPEC:spec/scoping/bulk_write_guard_spec.rb].

[ERROR:BulkWriteError] is raised by `update_all`, `delete_all` and `destroy_all` on a scoped relation when there is no current tenant, or when the relation is not provably pinned to the current tenant. `without_tenant` is the explicit override. Raised in [FILE:lib/tenancy_dable/relation_extension.rb]; proven by [SPEC:spec/scoping/bulk_write_guard_spec.rb] and [SPEC:spec/integration/bulk_write_flow_spec.rb].

[ERROR:CrossTenantError] is never raised by the gem. It is the home of the compatibility constant [CONST:CrossTenantError::MESSAGE], kept equal to the `en` default of `errors.messages.cross_tenant`. The cross-tenant `belongs_to` check adds the `:cross_tenant` key to the record's errors and does not raise, so the text comes from the locale files and a host override wins. [SPEC:spec/contract_spec.rb] pins the constant and its agreement with the locale files.

[ERROR:NotAMemberError] is raised by controller resolution when the acting user is not a member of the resolved tenant and `config.on_not_a_member` is `:not_a_member_error`, the default. The other modes raise `Pundit::NotAuthorizedError` or run the host's callable. Raised in [FILE:lib/tenancy_dable/controller/resolvable.rb]; proven by [SPEC:spec/resolution/not_a_member_behavior_spec.rb] and [SPEC:spec/resolution/membership_enforcement_spec.rb].

[ERROR:TenantNotFoundError] is raised by a `TenancyDable::Job` whose enqueue-time tenant id no longer resolves: running on would read and write every tenant's rows under the fail-open default. A job enqueued with no tenant performs untouched. A host can `discard_on` it. Raised in [FILE:lib/tenancy_dable/job.rb]; proven by [SPEC:spec/integration/active_job_propagation_spec.rb]. Slug resolution does not raise it: with `on_tenant_not_found` at `:raise` a missing slug raises `ActiveRecord::RecordNotFound` from `find_by!` ([SPEC:spec/resolution/tenant_not_found_spec.rb]).

[ERROR:TenantOverrideError] is raised when `current_tenant=` switches between two different, non-nil tenants while `config.audit_overrides` is `:raise`. Setting from nil, to nil, or to the same tenant is a normal establish or clear. It also surfaces when a snapshot restore re-establishes a different tenant under that setting. Raised in [FILE:lib/tenancy_dable.rb]; proven by [SPEC:spec/security/red_team_spec.rb] and [SPEC:spec/facade/snapshot_spec.rb].

[ERROR:CrossTenantReadError] is raised by the read guard when a read on a scoped relation is pinned to a tenant other than the current one, or has had its tenant filter removed, while a tenant is current. It is a sibling of `BulkWriteError`, with an ids-only message. Raised in [FILE:lib/tenancy_dable/relation_extension.rb]; proven by [SPEC:spec/scoping/read_guard_spec.rb]. `config.guard_reads` turns the guard off.

[ERROR:CrossTenantWriteError] is raised by the write guard when a create, update, destroy, touch, `update_columns` or `delete` names a tenant other than the current one, and by `insert_all` and `upsert` when a row targets another tenant, or an upsert's conflict target does not include the tenant column. It is a raise and not a validation error because a foreign tenant id is never user input in a correct host. Raised in [FILE:lib/tenancy_dable/scoped.rb] and [FILE:lib/tenancy_dable/insert_all_extension.rb]; proven by [SPEC:spec/scoping/create_refusal_spec.rb], [SPEC:spec/scoping/foreign_record_write_spec.rb], [SPEC:spec/scoping/tenant_assignment_spec.rb] and [SPEC:spec/scoping/insert_all_guard_spec.rb].

[ERROR:UnsafeIsolationError] is raised on every gem write to `Current` under a fiber scheduler while Active Support's isolation level is `:thread`, because every fiber on the thread would share one `Current`. `config.isolation_check` selects `:raise` (the default), `:warn` (log instead) or `:off`. Raised in [FILE:lib/tenancy_dable.rb]; proven by [SPEC:spec/facade/isolation_check_spec.rb].

[ERROR:BypassReasonError] is raised by `without_tenant` when `reason:` is neither nil, a String nor a Symbol, so a record can never reach the event payload, and when `config.require_bypass_reason` is on and the reason is nil or blank. Raised in [FILE:lib/tenancy_dable.rb]; proven by [SPEC:spec/facade/without_tenant_audit_spec.rb].

[ERROR:ConfigurationError] is raised by `Configuration#validate!` for an invalid setting, and by the declaration macros for an invalid or repeated tenancy declaration (a blank `because:`, a bad `tag:` or `allow_tenant_fk:`, a second declaration). Both are class-load or boot-time misconfiguration, and neither is a runtime tenant event. Raised in [FILE:lib/tenancy_dable/configuration.rb] and [FILE:lib/tenancy_dable/declarations.rb]; proven by [SPEC:spec/configuration_spec.rb] and [SPEC:spec/declarations/declarations_spec.rb].

## Principles

[RULE:every gem error descends from TenancyDable::Error] A new error never inherits from `StandardError` directly or from an Active Record class.

[RULE:messages carry identifiers, never payloads] Guard messages name the model and tenant ids only, so a rescued error written to a log leaks no row data. [ERROR:NotAMemberError] names the tenant slug the request carried and [ERROR:ConfigurationError] names the offending setting value; none carries a record or its attributes.

[RULE:the validation path uses a key, the guard path raises] The cross-tenant `belongs_to` check goes through the `errors.messages.cross_tenant` locale key; the read, write and bulk guards raise their own class. See [REF:i18n.md] for the keys.

## Adding an error

If you add an error class, also update, in the same change:

1. [FILE:lib/tenancy_dable/errors.rb], with a comment saying what raises it.
2. [FILE:spec/contract_spec.rb]: the list of names in "Error hierarchy", and its title if it carries a count.
3. The `## Errors` table in [FILE:README.md]: one row saying when it is raised.
4. The error counts in [FILE:DESIGN.md]: the module table row, the layering diagram, and the current-release delta that lists the errors.
5. A spec that triggers the raise and asserts the class, next to the code that raises it.
6. The comment text in [FILE:lib/generators/tenancy_dable/install/templates/initializer.rb.tt] when the error is governed by a setting.
7. This file and [FILE:.claude/rules/errors.md].

## Gotchas

### Gotcha: Rescuing the wrong class for a missing slug

[SYMPTOM:`rescue TenancyDable::TenantNotFoundError` around a request never fires for an unknown slug]. [CAUSE:resolution with `on_tenant_not_found` at `:raise` uses `find_by!`, which raises `ActiveRecord::RecordNotFound`; `TenantNotFoundError` belongs to the job path]. [FIX:rescue `ActiveRecord::RecordNotFound` in the controller, or set `on_tenant_not_found` to `:null`]. [RULE:the two not-found conditions have two classes].

## Related

The guards that raise: [REF:scoping.md], [REF:context.md]. Jobs: [REF:jobs.md]. Resolution: [REF:resolution.md]. Settings that choose between raising and not: [REF:configuration.md].
