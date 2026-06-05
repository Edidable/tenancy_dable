# v0.3 Phase 01 — Job carries membership (closes the ActiveJob caveat)

**Read `.midgal/V03_PLAN.md` (§B) + the phase-00 scratchpad.** Verify phase 00 landed.

## Files
- `lib/tenancy_dable/job.rb`:
  - add `SERIALIZED_MEMBERSHIP_KEY = "tenancy_dable_membership_id"` and `attr_accessor :tenancy_dable_membership_id`.
  - `serialize` merges the membership id (`tenancy_dable_membership_id || TenancyDable.current_membership&.id`) alongside the existing tenant id.
  - `deserialize` reads it into the accessor.
  - `around_perform`: after restoring the tenant, reload the membership via
    `TenancyDable.configuration.membership_class.find_by(id: tenancy_dable_membership_id)`
    (when present) and set `TenancyDable.current_membership` for the block. Do this
    INSIDE the existing `with_tenant` block so its `ensure` clears it — no leak across pooled jobs.
  - **Keep unchanged:** enqueue-time capture; a nil/deleted tenant still runs
    `with_tenant(nil)` (do not "fix" these — V03_PLAN guardrail). A nil membership id ⇒ nil membership.
- `spec/integration/active_job_propagation_spec.rb` (extend): assert that a job enqueued
  with a current membership restores BOTH `current_tenant` and `current_membership` in
  `perform`; that an older-style payload (no membership key) still restores the tenant
  and a nil membership; that nothing leaks after `perform`.

## Acceptance / Validation
- `bundle exec rspec spec/integration` green.
- Existing tenant-propagation behavior unchanged.

## On completion
Scratchpad: how membership is serialized/reloaded; confirm backward compatibility.
