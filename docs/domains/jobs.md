# Jobs: tenant and membership propagation through Active Job

A background job must run under the same workspace as the request that enqueued it, or its reads and bulk writes would see every tenant. [MODULE:TenancyDable::Job] in [FILE:lib/tenancy_dable/job.rb] carries the tenant and the acting membership through the serialized job payload and restores both for the duration of `perform`, so the job's scoped reads filter and its bulk writes pass the guard exactly as they would have inline, with no tenant id threaded through the job's arguments.

## Opt-in wiring

The entry file does not require the job concern, so Active Job stays an optional dependency. A host that runs jobs writes [REQUIRE:require "tenancy_dable/job"] and has its `ApplicationJob` (an `ActiveJob::Base` subclass) `include TenancyDable::Job`. The concern is an `ActiveSupport::Concern` ([SPEC:spec/contract_spec.rb], "defines TenancyDable::Job as a concern") that adds an `around_perform` callback, overrides `serialize` and `deserialize`, and adds the accessors `tenancy_dable_tenant_id` and `tenancy_dable_membership_id`.

## What travels

At enqueue, Active Job calls `serialize`, and the concern merges two keys into the payload: [KEY:tenancy_dable_tenant_id] holds the id of `TenancyDable.current_tenant`, and [KEY:tenancy_dable_membership_id] holds the id of the stored membership. The two key names carry the gem's prefix so they cannot collide with a host's own serialized arguments; the constants are `SERIALIZED_TENANT_KEY` and `SERIALIZED_MEMBERSHIP_KEY`. An id already set on the job instance wins over the live context, so a retry that re-serializes after a restore keeps the original ids. The value is nil when no tenant or no membership was current.

The membership id comes from `TenancyDable::Current.membership`, the stored value, and not from the `current_membership` reader. A job enqueued inside `with_tenant(other)` while the stored membership belongs to a different tenant therefore still carries that membership. On the worker side that membership is restored as stored and reads as foreign, not as current. [SPEC:spec/integration/active_job_propagation_spec.rb] proves each step: the tenant id in the payload, the membership id in the payload, both restored on a worker that had nothing ambient, and "carries a membership of another tenant, which is not current inside perform" (the job's tenant is B, `current_membership` is nil, the stored membership is still A's).

`deserialize` reads the two keys back into the accessors. A payload without the membership key restores the tenant and a nil membership; the "restores the tenant but a nil membership" example in [SPEC:spec/integration/active_job_propagation_spec.rb] proves it.

The bypass flag does not travel. The payload has no key for `tenant_scope_disabled`, so a job enqueued inside `without_tenant` runs scoped, under its tenant or under none; a job that needs the bypass calls `without_tenant(reason:)` itself.

## What `perform` does

The `around_perform` callback reads the tenant id from the job and branches:

- A nil tenant id, a job enqueued with no current tenant, performs untouched. That is fail-open, mirroring the default scope with `require_tenant` off ([SPEC:spec/integration/active_job_propagation_spec.rb], "round-trips a nil tenant when enqueued with no current tenant (fail-open)"). A membership id with no tenant id is not restored.
- Otherwise the tenant is reloaded by id with `TenancyDable.configuration.tenant_class.find_by(id:)`, so `perform` gets a live record and never a stale one. The block then runs inside `TenancyDable.with_tenant(tenant)`, and inside that block the membership is reloaded with `membership_class.find_by(id:)` and assigned through `current_membership=`. A nil or absent membership id leaves the membership nil, and so does a membership row that was deleted after the enqueue.

Both are torn down by the `ensure` of `with_tenant`, which puts back the worker thread's own tenant and membership, so a pooled worker never carries one job's context into the next ([SPEC:spec/integration/active_job_propagation_spec.rb], "leaves no tenant set after the job finishes" and "leaves no membership set after the job finishes"). Because the restore goes through `with_tenant`, the isolation check, the audit-override policy and the RLS statement apply in the worker as for any other writer (`docs/domains/context.md`). The job's reads scope: "scopes the job's own queries to the restored tenant" runs a `Widget` query inside `perform` and sees only the enqueuing tenant's rows.

## A vanished tenant raises

If the stored tenant id no longer resolves, `perform` raises [ERROR:TenancyDable::TenantNotFoundError] and runs no work. The message is `"<JobClass> was enqueued in tenant #<id>, which no longer resolves; refusing to run it with no tenant"`, and it names ids only. The rule exists because running on with no tenant would execute under the fail-open default, so a cleanup or purge job could read and write every tenant's rows; an unresolved id is a different case from a nil id, which is a job deliberately enqueued with no tenant. The lookup goes through the tenant class, so a tenant destroyed and a tenant hidden by a host default scope are both "no longer resolves". [SPEC:spec/integration/active_job_propagation_spec.rb] ("raises TenantNotFoundError when the enqueue-time tenant no longer resolves") proves the exact message, that the job's work did not run, and that no tenant is left current.

The job does not discard itself. A host that wants a vanished tenant to end the job quietly declares [DIRECTIVE:discard_on TenancyDable::TenantNotFoundError] on its `ApplicationJob`; without it Active Job's own retry and failure handling applies to the raise.

## Spec harness note

Active Job clears `Current` the instant `perform` returns, so the spec's probe job records what it observed during `perform` into class-level sinks, and the job class is a named class so `ActiveJob::Base.execute` can constantize it from the payload.

## Gotchas

### Gotcha: A job that needs the bypass inherits none

[SYMPTOM:a job enqueued from inside a `without_tenant` block reads only one tenant's rows, or raises `NoTenantError` with `require_tenant` on]. [CAUSE:the payload carries the tenant and the membership ids and never the `tenant_scope_disabled` flag]. [FIX:call `TenancyDable.without_tenant(reason: "...")` inside `perform`]. [RULE:the bypass is declared where the cross-tenant work happens, never inherited through the queue].
