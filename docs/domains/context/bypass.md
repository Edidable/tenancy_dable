# The audited bypass: `without_tenant(reason:)`

> Part of the [context domain](../context.md).

[METHOD:TenancyDable.without_tenant] runs a block with tenant scoping disabled and returns the block's value. It sets `Current.tenant_scope_disabled` to true for the block and restores the prior value in `ensure`, so nesting is safe. It does not touch the current tenant, so the audit-override policy and the RLS hook do not fire. While the flag is set, scoped models return `all`, the read guard and the bulk-write guard step aside, and the relations built inside carry the `BuiltWithoutTenant` marker (`docs/domains/scoping.md`). `with_tenant(nil)` is a different thing: it clears the tenant but leaves scoping on.

## Order of the steps

The signature is [METHOD:without_tenant(reason: nil)]. The steps run in a fixed order, and a failure at any step stops the later ones:

1. The reason type is checked. A `reason` that is not nil, a String or a Symbol raises [ERROR:TenancyDable::BypassReasonError], whatever `require_bypass_reason` says, before the isolation check, the event or any state change. This keeps a record, a Hash or an exception out of the event payload through `reason:`. [SPEC:spec/facade/without_tenant_audit_spec.rb] runs an Object, an Integer, an Array, a Hash, a Float and `true` and proves no event and no state change for each.
2. When [CONFIG:require_bypass_reason] is true and the reason is blank (nil, empty, or whitespace only after `to_s.strip`), the same error is raised, with no event and no state change ([SPEC:spec/facade/without_tenant_audit_spec.rb], "raises BypassReasonError for nil", `""` and `"   "`).
3. The isolation check runs (`docs/domains/context/fiber-safety.md`).
4. The event is emitted, only if someone is subscribed.
5. The flag is set, the block yields, the prior flag is restored.

The reason types are exactly String and Symbol, and nil when the setting is off. [CONFIG:require_bypass_reason] defaults to false and `validate!` rejects anything but true or false with `ConfigurationError`. With the setting on, a host gets a bypass that cannot be written without a stated reason.

## The event

The event name is the constant [CONSTANT:TenancyDable::WITHOUT_TENANT_EVENT], the string [EVENT:without_tenant.tenancy_dable] ([SPEC:spec/tenancy_dable_spec.rb] locks it; so does `spec/contract_spec.rb`). It is emitted with `ActiveSupport::Notifications.instrument` and [RULE:no block].

The payload has exactly three keys, [PAYLOAD_KEY:reason], [PAYLOAD_KEY:tenant_id] and [PAYLOAD_KEY:call_site]; [SPEC:spec/facade/without_tenant_audit_spec.rb] ("emits the event with exactly reason, tenant_id and call_site") asserts the key set:

- [PAYLOAD_KEY:reason] is the value the caller passed, unchanged: a String or a Symbol, or nil when omitted.
- [PAYLOAD_KEY:tenant_id] is the id of the tenant that is current when the bypass starts, or nil when none is current. The bypass does not change the tenant, so it is also the tenant inside the block.
- [PAYLOAD_KEY:call_site] is the string `"<path>:<line>"` of the first caller outside the gem's `lib/` directory, or nil when there is none. The path is the frame's `absolute_path` when Ruby knows one, so it is an absolute path, and only falls back to the relative path otherwise. [SPEC:spec/facade/without_tenant_audit_spec.rb] ("points call_site at the file and line that called without_tenant, not the gem") compares it with `"#{__FILE__}:#{line}"`.

Two properties are deliberate:

- The event is emitted without a block. With a block, `ActiveSupport::Notifications` adds `:exception` and `:exception_object` to the payload when the block raises, and an exception can carry a record (`ActiveRecord::RecordInvalid#record`) that a subscriber logging the payload would leak. Without a block the payload is always the three keys, and the event marks where a bypass begins and has no duration. [SPEC:spec/facade/without_tenant_audit_spec.rb] ("emits the payload without a block, so a raising block adds no exception keys" and "puts no record in the payload when the block raises") proves it.
- The event is emitted only when it is subscribed. The facade asks `ActiveSupport::Notifications.notifier.listening?` first; with no subscriber, neither the event nor `call_site` is computed. [SPEC:spec/facade/without_tenant_audit_spec.rb] ("without_tenant with no subscriber") proves that `call_site` is not called and `instrument` is not called.

A subscriber that raises stops the bypass before it starts: the event runs before the flag is set, so the block never runs and the flag keeps its prior value. This is fail-closed ([SPEC:spec/facade/without_tenant_audit_spec.rb], "never lets a subscriber failure start the bypass").

Every nested call reports itself. A `without_tenant` inside another emits a second event with its own call site and the same tenant id, and each level restores the prior flag on normal exit and on raise ([SPEC:spec/facade/without_tenant_audit_spec.rb], "nesting").

## The record never reaches the event

The payload carries the host's reason, a tenant id and a `file:line`, and never a record: [RULE:security invariant 6, audit output carries ids and never record data] (`DESIGN.md` §11). The gem persists nothing and writes no log line of its own for the bypass; a host that wants a log or a metric subscribes to the event. A host should not put record data into a reason, because the reason is passed through unchanged. No code inside the gem calls `without_tenant` itself.

## A snapshot reports nothing

Restoring a snapshot taken inside `without_tenant` sets the flag with no reason check and no event: the bypass was reported where it began. [SPEC:spec/facade/snapshot_spec.rb] ("restores the flag of a snapshot taken in without_tenant with no event and no reason check") proves it with `require_bypass_reason` on and a subscriber attached.

## Gotchas

### Gotcha: The call site names the first caller outside the gem

[SYMPTOM:a subscriber receives a call site that points at a wrapper in the host and not at the code that wanted the bypass]. [CAUSE:`call_site` is the first frame outside the gem's own directory, so a host helper that wraps `without_tenant` is what the event names]. [FIX:put the wrapper's own caller into the `reason:` string, or call `without_tenant` at the site that needs it]. [RULE:the call site is the caller of the facade method, whoever that is].
