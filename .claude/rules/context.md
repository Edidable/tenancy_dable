---
paths:
  - "lib/tenancy_dable.rb"
  - "lib/tenancy_dable/current.rb"
  - "lib/tenancy_dable/snapshot.rb"
  - "spec/facade/**"
  - "spec/tenancy_dable_spec.rb"
  - "spec/integration/cross_tenant_isolation_spec.rb"
  - "spec/integration/rls_toggle_spec.rb"
  - "spec/scoping/rls_spec.rb"
---
`Current` holds raw state and no behaviour. The isolation check runs in every facade writer (`current_tenant=`, `current_membership=`, `without_tenant`, and through them `with_tenant` and `Snapshot#restore`); the audit-override policy and the RLS hook run in `current_tenant=` only; the bypass event belongs to `without_tenant`. Never write `Current.tenant=` / `Current.set` for tenant state: it skips all of them.
The isolation check runs FIRST in every gem write to `Current`, before anything is written, and fires only with a fiber scheduler AND thread isolation. Modes: `:raise` (default, `UnsafeIsolationError`, nothing written), `:warn` (log every write, then write), `:off` (evaluates nothing). A new writer of `Current` calls `check_isolation!` first; `spec/facade/isolation_check_spec.rb` lists the writers.
A thread or fiber that lost the context is fail-OPEN with `require_tenant` off (it reads every tenant). Hosts running threads or fibers set `require_tenant = true` and hand the context over with `TenancyDable.carry`; do not write docs or specs that call a lost context "fail closed".
`snapshot` captures RAW stored state (`Current.membership`, not the reader). `Snapshot#restore` goes through `with_tenant`, then `current_membership=`, then the private flag writer: so the check, audit override and RLS all apply, and the restoring thread's own state returns on exit or raise. A snapshot taken inside `without_tenant` restores the flag with no reason check and no event.
`current_membership` answers only while `membership.tenant_id` is the current tenant's; `foreign_membership?` is true when one is stored but not current's (also with no tenant). Anything that carries a membership reads `Current.membership`. A nil `current_membership` is not a system context without `foreign_membership?`.
`with_tenant` restores the prior tenant and membership in `ensure` THROUGH the writers, so the RLS statement re-fires on exit; keep it that way.
An audit override is a switch between two different non-nil tenants only; messages and logs carry ids, never names or records.
`without_tenant` order: reason type check, `require_bypass_reason` blank check, isolation check, event, flag. Reasons accepted: nil, String, Symbol; anything else raises `BypassReasonError` always. Event `without_tenant.tenancy_dable`: exactly the keys `reason`, `tenant_id`, `call_site`; emitted WITHOUT a block, and only when `listening?` (no subscriber: no event, no `call_site`); `call_site` is a `path:line` outside `lib/`, absolute when Ruby knows it.
Never give the event a block or add a payload key: a raising block would put an exception (which can carry a record) in the payload.
If you change a facade method, also `spec/contract_spec.rb` (method list, defaults) and the README facade and security sections.
Proof: `spec/facade/isolation_check_spec.rb`, `spec/facade/snapshot_spec.rb`, `spec/facade/without_tenant_audit_spec.rb`, `spec/integration/cross_tenant_isolation_spec.rb` (membership), `spec/integration/rls_toggle_spec.rb`.
Narrative: docs/domains/context.md
