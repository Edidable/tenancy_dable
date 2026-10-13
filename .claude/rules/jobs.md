---
paths:
  - "lib/tenancy_dable/job.rb"
  - "spec/integration/active_job_propagation_spec.rb"
---
`TenancyDable::Job` is opt-in: the entry file must not require it (`require "tenancy_dable/job"` is the host's); Active Job stays an optional dependency.
The payload keys are `tenancy_dable_tenant_id` and `tenancy_dable_membership_id`; renaming one breaks jobs already enqueued. An id already set on the job (a retry) wins over the live context.
The membership id comes from `TenancyDable::Current.membership` (stored), never from `current_membership`, so a membership of another tenant still travels and reads as foreign in `perform`.
A payload without the membership key restores the tenant and a nil membership; a deleted membership reloads to nil.
Tenant id nil: `perform` runs untouched (fail-open, like the default scope with `require_tenant` off). Tenant id present but no longer resolving through `tenant_class.find_by(id:)`: raise `TenantNotFoundError` and run nothing, never run on with no tenant.
The restore goes through `with_tenant` and sets the membership inside that block, so its `ensure` tears both down; do not set the membership outside it.
The bypass flag is not in the payload; a job that needs it calls `without_tenant(reason:)` itself.
Do not rescue `TenantNotFoundError` inside the concern; a host opts into `discard_on`.
If you change the payload or the restore order, also `spec/integration/active_job_propagation_spec.rb` and the job section of the README and `UPGRADING.md`.
Proof: `spec/integration/active_job_propagation_spec.rb` (serialize/execute round trips, vanished tenant message, foreign membership, a payload without the membership key).
Narrative: docs/domains/jobs.md
