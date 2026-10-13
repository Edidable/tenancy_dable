# Context: the `TenancyDable` facade and the current tenant

The tenant context is the state every other layer reads: the default scope, the read guard, the bulk-write guard, the controller concern, the Cable concern and the job concern all ask "which tenant is current" and nobody else writes the answer. This hub covers the facade that owns that state. Two spokes carry the rest of the domain.

## Spokes

- [SPOKE:docs/domains/context/fiber-safety.md] holds the isolation check, the `snapshot`/`restore`/`carry` carrier, and what a thread or fiber that lost the context does.
- [SPOKE:docs/domains/context/bypass.md] holds the audited `without_tenant(reason:)`, its event, and `require_bypass_reason`.

## Raw state versus behaviour

The state lives in [CLASS:TenancyDable::Current] (`lib/tenancy_dable/current.rb`), an `ActiveSupport::CurrentAttributes` with three attributes: [ATTRIBUTE:tenant], [ATTRIBUTE:membership] and [ATTRIBUTE:tenant_scope_disabled]. `Current` holds raw values and no behaviour, so that the audit-override policy, the RLS hook, the isolation check and the bypass event live in exactly one place, the facade in [FILE:lib/tenancy_dable.rb]. The isolation check runs in every facade writer; the audit-override policy and the RLS statement run in `current_tenant=` only, which `with_tenant` and `Snapshot#restore` go through, and the bypass event belongs to `without_tenant`. A host writes tenant state through [METHOD:TenancyDable.current_tenant=], [METHOD:TenancyDable.current_membership=], [METHOD:TenancyDable.with_tenant] and [METHOD:TenancyDable.without_tenant], and reads it through [METHOD:TenancyDable.current_tenant] and [METHOD:TenancyDable.current_membership]. Rails resets `Current` between requests and the spec harness resets it after each example.

A write that goes to `Current` directly (`Current.tenant = ...`, `Current.set(...)`, `Current.tenant_scope_disabled = ...`) skips the isolation check, the audit-override policy and the RLS statement together; there is [ABSENCE:no guard on direct Current writes], because `Current` is raw state, and a host that writes it has chosen to leave the facade. No spec asserts the skip; `spec/scoping/read_guard_spec.rb` uses `Current.set` on purpose to build a relation under a different context than the one it is read in.

## The current membership answers only inside its own tenant

[METHOD:TenancyDable.current_membership] returns the stored membership only while its `tenant_id` equals the current tenant's id, and returns `nil` otherwise, including when no tenant is current. The stored value is untouched, so leaving a `with_tenant(other)` block puts the original membership back in view. The reason is that a policy built inside `with_tenant(other)` must never decide with a role earned in the tenant it left: [SPEC:spec/integration/cross_tenant_isolation_spec.rb] ("the current membership") proves a nil membership inside the inner tenant, the original again after the block, and a `Policy::Base` that denies a manager of tenant A acting inside tenant B.

[METHOD:TenancyDable.foreign_membership?] is true when a membership is stored but is not the current tenant's, which includes the case of no current tenant at all. It exists because a nil `current_membership` is ambiguous: a host that reads nil as "this is a system context" must also check `foreign_membership?`, or a carried membership from another tenant will pass for a system caller. [SPEC:spec/integration/cross_tenant_isolation_spec.rb] ("foreign_membership?") proves it false with no membership, false in the membership's own tenant, true inside another tenant, and true under `with_tenant(nil)`.

Anything that must carry the stored membership (the job payload, a snapshot) reads [ATTRIBUTE:Current.membership], not the reader, so a membership of another tenant still travels and still reads as foreign on the other side (`docs/domains/jobs.md`, `docs/domains/context/fiber-safety.md`).

## `with_tenant` nests and restores through the writer

[METHOD:TenancyDable.with_tenant] saves the prior tenant and membership, assigns the new tenant through `current_tenant=`, yields, and in `ensure` assigns the prior tenant and the prior membership back, also through the facade writers. It returns the block's value. Routing the restore through the writer matters for three reasons at once: the RLS hook fires on exit, the isolation check applies on exit, and the audit-override policy sees the way back too. [SPEC:spec/integration/rls_toggle_spec.rb] proves the second RLS statement on restore ("re-fires on restore so an enabled RLS session never stays pointed at an inner tenant"). Entering a block with `with_tenant(nil)` clears the tenant for the block and is how code runs with no tenant without disabling scoping.

`with_tenant` is not the bypass: inside it the default scope still filters, to the new tenant. [METHOD:TenancyDable.without_tenant] disables scoping instead (`docs/domains/context/bypass.md`).

## The audit-override policy

Only a switch between two different, non-nil tenants counts as an override. Setting from nil, setting to nil, and setting the same tenant are an ordinary establish or clear, and never an override. The behaviour of an override is [CONFIG:audit_overrides]: `:log` (the default) writes a warning to the Rails logger naming the two tenant ids, `:raise` raises [ERROR:TenancyDable::TenantOverrideError], and `:ignore` does nothing. Both the log line and the error message carry tenant ids only and never a name, slug or record; [SPEC:spec/security/red_team_spec.rb] proves it for the raise message ("names only ids in the raise-mode override error, never payload") and for the log line ("logs only ids on an override"), and the latter also proves that establishing from nil is no override. A nested `with_tenant(B)` inside `with_tenant(A)` is a switch on entry and again on the way back, because both go through `current_tenant=`; [SPEC:spec/facade/snapshot_spec.rb] ("treats restoring into a different tenant as a switch") proves the same rule for `Snapshot#restore`.

## The RLS hook

[CONFIG:rls] is off by default. When it is on and the effective tenant id actually changes, `current_tenant=` runs the SQL string returned by [CONFIG:rls_statement] (a callable that receives the new tenant, or nil) against the Active Record connection; a nil statement is skipped. The default statement is `SET app.tenant_id = <quoted id>`. Because `with_tenant` and `Snapshot#restore` write through `current_tenant=`, the statement tracks entry and restore alike. [SPEC:spec/integration/rls_toggle_spec.rb] proves the statement per switch, the re-fire on restore, and that a disabled hook does not touch the connection with a statement.

## `pundit_context`

[METHOD:TenancyDable.pundit_context] takes `user:`, `tenant:` and `membership:` keywords and builds a `TenancyDable::Policy::Context`, the triple that policies and `policy_scope` decide on instead of a bare user, because one user holds a different role, or none, in each tenant. The facade only builds the value; the policy rules are in the authorization domain. [SPEC:spec/contract_spec.rb] locks the keyword signature, and `spec/security/red_team_spec.rb` builds contexts through it.

## What the contract spec locks

[SPEC:spec/contract_spec.rb] locks the facade's public method list (including `snapshot`, `carry` and `audit`), the default of each setting, and the member list of `Snapshot`. [SPEC:spec/tenancy_dable_spec.rb] locks the event name constant [CONSTANT:TenancyDable::WITHOUT_TENANT_EVENT] and that the gem's directory constant used by `call_site` is private.
