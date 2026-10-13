# Fiber safety: the isolation check and the context carrier

> Part of the [context domain](../context.md).

`TenancyDable::Current` is an `ActiveSupport::CurrentAttributes`, so it is isolated per thread under Rails' default [CONFIG:active_support.isolation_level = :thread]. Two things follow, and this spoke covers both: under a fiber scheduler every fiber on a thread shares one `Current`, and work handed to a different thread or fiber starts with no tenant at all.

## The isolation check

The check is the private facade method [METHOD:TenancyDable.check_isolation!] in [FILE:lib/tenancy_dable.rb]. It fires when two conditions hold together: [RULE:Fiber.scheduler is non-nil] on the writing thread, and [RULE:ActiveSupport::IsolatedExecutionState.isolation_level is :thread]. Under those conditions fibers on the thread can interleave while they share one `Current`, a live cross-request leak. A blocking fiber on a thread with a scheduler counts, because the test is the scheduler's presence and not the writing fiber's behaviour. Puma, Sidekiq and rake run no scheduler, so the check does nothing there, unless host code opens an `Async { }` or `Sync { }` reactor inside them: that sets the scheduler for the thread and the check fires under thread isolation.

It runs first in every gem write to `Current`, before anything is written. The writers that carry it are [METHOD:TenancyDable.current_tenant=], [METHOD:TenancyDable.current_membership=], and the private writer of `tenant_scope_disabled` that `Snapshot#restore` uses. [METHOD:TenancyDable.with_tenant] is covered through `current_tenant=`, on entry and again in its `ensure`; [METHOD:TenancyDable.without_tenant] runs the check itself (after its reason checks, before its event) and then sets the flag with the check disabled so it does not run twice. [SPEC:spec/facade/isolation_check_spec.rb] runs every mode against the five entry points `current_tenant=`, `current_membership=`, `with_tenant`, `without_tenant` and `Snapshot#restore`, and proves that a raising call writes nothing: tenant, membership and flag all stay nil.

[CONFIG:isolation_check] has three modes, and `validate!` rejects any other value with `ConfigurationError` ([SPEC:spec/configuration_spec.rb]):

- [MODE:raise] is the default. The write raises [ERROR:TenancyDable::UnsafeIsolationError] and writes nothing.
- [MODE:warn] logs `[TenancyDable] <message>` on every detected write through the facade's logger, then performs the write. It logs each time, like `audit_overrides: :log`, because the condition is a live leak and not a one-off.
- [MODE:off] evaluates nothing: it does not even read `Fiber.scheduler`.

The message is [MESSAGE:tenant state written under a fiber scheduler with thread isolation; set config.active_support.isolation_level = :fiber] in both raising and logging, and it carries no ids ([SPEC:spec/facade/isolation_check_spec.rb], "carries no ids in the message"). The error descends from `TenancyDable::Error`. The fix a host applies is the message's own: set Active Support's isolation level to `:fiber`. [SPEC:spec/facade/isolation_check_spec.rb] runs a real `Async` reactor and proves both outcomes: it raises under thread isolation, and under `:fiber` isolation each fiber keeps its own tenant.

## Write only through the facade

The isolation check runs in every facade writer; the audit-override policy and the RLS statement run in `current_tenant=` only, which `with_tenant` and `Snapshot#restore` go through. A write straight to `TenancyDable::Current` skips all three, so a host that writes `Current.tenant = tenant` under a scheduler gets no raise, no audit and no RLS statement. This is a documented bypass and not a guarded path; the reads of `Current` carry no check, because only writes can leak.

## A thread or fiber that lost the context is fail-OPEN

A new thread starts with an empty `Current`; [SPEC:spec/facade/snapshot_spec.rb] ("starts a plain thread with no tenant") proves `Thread.new { TenancyDable.current_tenant }.value` is nil. That is not fail-closed. What the thread does next depends on [CONFIG:require_tenant]. With it off (the default) the default scope takes its fail-open branch and the thread reads every tenant's rows ([SPEC:spec/scoping/default_scope_spec.rb], "returns every row when require_tenant is falsy and no tenant is set"); the relations it builds carry the `BuiltWithoutTenant` marker, but with no current tenant the read guard has nothing to compare the marker against, so nothing refuses. With it on, the same thread raises [ERROR:TenancyDable::NoTenantError] ([SPEC:spec/scoping/default_scope_spec.rb], "raises NoTenantError when require_tenant is truthy and no tenant is set").

Fibers are no safer than threads here. Under `:fiber` isolation Active Support keeps the state in a per-fiber slot that a child fiber does not inherit, so a fiber spawned inside a request (an `Async` task, `Fiber.new`, an `Enumerator` advanced with `next`) also starts with no tenant, and with `require_tenant` off it also reads every tenant. The check reports nothing in that case, because `:fiber` isolation is the setting it asks for.

The gem keeps this behaviour and does not add a "context lost" marker (for example in Ruby fiber storage, which children do inherit): [RESIDUAL:a lost context with require_tenant off reads every tenant] is stated and not detected, because `require_tenant` is already the one switch that decides what "no tenant" means. The recommendation for a host that runs threads, a thread pool or fibers is therefore two settings together: [RECOMMENDATION:config.require_tenant = true] so a lost context raises, and [RECOMMENDATION:TenancyDable.carry] to hand the context across so the work has a tenant to run under.

## The carrier: `snapshot`, `restore`, `carry`

[METHOD:TenancyDable.snapshot] returns a [CLASS:TenancyDable::Snapshot], a `Data.define(:tenant, :membership, :tenant_scope_disabled)` in [FILE:lib/tenancy_dable/snapshot.rb]. It captures the raw stored state: `membership` is `Current.membership` and not the `current_membership` reader, so a membership of another tenant is captured as set and still reads as foreign on the other side ([SPEC:spec/facade/snapshot_spec.rb], "captures a foreign membership as set, not the reader's nil"). On a clean thread the snapshot is all nil. A snapshot taken inside `without_tenant` captures the flag as true.

[METHOD:Snapshot#restore] takes a block and routes the tenant through `TenancyDable.with_tenant`:

1. `with_tenant(tenant)` runs, so the isolation check, the audit-override policy and the RLS statement all apply, and the RLS statement fires on entry and again on restore ([SPEC:spec/facade/snapshot_spec.rb], "fires the RLS statement on entry and on restore").
2. Inside, `current_membership=` sets the carried membership, and `with_tenant`'s `ensure` puts the restoring thread's own membership back.
3. The private flag writer sets the carried `tenant_scope_disabled` for the block and restores the prior flag in its `ensure`.

On normal exit and on raise, the restoring thread's own tenant, membership and flag come back: nil, nil, nil on a fresh or pooled thread, so a pooled thread never keeps another request's tenant ([SPEC:spec/facade/snapshot_spec.rb], "resets to nil/nil/nil on normal exit", "resets on raise and re-raises", "puts back the restoring thread's own prior state"). Restoring into a thread already inside a different tenant is a switch like a nested `with_tenant`, so the audit-override policy applies ("treats restoring into a different tenant as a switch"). Restoring a snapshot taken inside `without_tenant` sets the flag with no reason check and no event, because the bypass was reported where it began ("restores the flag of a snapshot taken in without_tenant with no event and no reason check"). Inside `restore`, `current_membership` follows the usual rule: nil, and `foreign_membership?` true, when the carried membership is not the carried tenant's. `restore` without a block raises `LocalJumpError`, as `with_tenant` without a block does.

[METHOD:TenancyDable.carry] takes a block and returns a lambda taking any positional and keyword arguments. It takes the snapshot when `carry` is called, not when the lambda runs, and the lambda runs the block inside `restore`:

```ruby
Thread.new(&TenancyDable.carry { work })
executor.post(&TenancyDable.carry { work })
```

[SPEC:spec/facade/snapshot_spec.rb] proves argument forwarding and the return value, the snapshot-at-carry-time rule, that the result is a lambda, `Thread.new(&carry)`, an `Async` task under `:fiber` isolation, and `LocalJumpError` without a block.

## Testing a thread or fiber

Assert `Current` state, never run a query, inside a spawned thread or fiber or while the isolation level is toggled. Each of those checks out its own database connection, outside the example's transaction, so a query there sees a different database state than the example created. Build records before the reactor starts and before toggling the level, and restore the level in an `ensure`; [SPEC:spec/facade/isolation_check_spec.rb] ("with a real Async reactor") follows this.

## Gotchas

### Gotcha: A carried block that outlives its snapshot

[SYMPTOM:a background task reads or writes under the tenant that was current when the task was scheduled, not the one current when it runs]. [CAUSE:`carry` takes its snapshot at call time]. [FIX:call `carry` where the work is handed off, inside the request's context, and never memoize the returned lambda across requests]. [RULE:a carried lambda is bound to one tenant context for its lifetime].
