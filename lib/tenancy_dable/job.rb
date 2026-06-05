# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # ActiveJob tenant propagation (DESIGN.md §10-I; PLAN mission "ActiveJob tenant
  # propagation"). A host's `ApplicationJob` does `include TenancyDable::Job` so a
  # background job runs under the SAME workspace as the request that enqueued it:
  # the current tenant's id is captured into the serialized job payload at enqueue
  # and restored as `TenancyDable.current_tenant` for the duration of `perform` in
  # the worker. The job's reads therefore scope, and its bulk writes pass the
  # guard, exactly as they would have inline — without the host threading a
  # tenant id through every job's arguments.
  #
  # The enqueue-time MEMBERSHIP travels the same way (v0.3.0): the acting
  # membership's id is captured alongside the tenant id and restored as
  # `TenancyDable.current_membership` for `perform`, so a job's context — tenant
  # AND role — matches the request's. The membership is set INSIDE the same
  # `with_tenant` block, so that block's `ensure` tears it down with the tenant
  # (no leak across pooled jobs). Backward compatible: an older payload without
  # the membership key restores a nil membership and the unchanged tenant.
  #
  # OPT-IN: this file is deliberately NOT required by the gem entry point, so
  # ActiveJob stays an OPTIONAL dependency — a host wires it up only if it runs
  # jobs (`require "tenancy_dable/job"`). The including class must be an
  # `ActiveJob::Base` subclass; the concern uses `around_perform` / `serialize` /
  # `deserialize`, which that base provides.
  module Job
    extend ActiveSupport::Concern

    # The payload keys the tenant id and membership id travel in. Namespaced so
    # they can never collide with a host's own serialized job arguments.
    SERIALIZED_TENANT_KEY = "tenancy_dable_tenant_id"
    SERIALIZED_MEMBERSHIP_KEY = "tenancy_dable_membership_id"

    included do
      # Restore the enqueue-time tenant for the whole of `perform`, then tear it
      # back down (via `with_tenant`'s ensure) so a pooled worker thread never
      # leaks one job's tenant into the next. A nil id — a job enqueued with no
      # current tenant — performs untouched (fail-open, mirroring the default
      # scope). The tenant is re-loaded by id so `perform` gets a live record.
      #
      # The membership is reloaded and set INSIDE the `with_tenant` block: that
      # block's `ensure` restores the prior membership too (lib/tenancy_dable.rb),
      # so the membership is torn down with the tenant and never leaks. The reload
      # is by id (a live record); a nil/absent membership id leaves it nil — older
      # payloads, or jobs enqueued with a tenant but no membership, simply run with
      # `current_membership` nil. A deleted membership reloads to nil all the same.
      around_perform do |job, block|
        tenant_id = job.tenancy_dable_tenant_id
        if tenant_id.nil?
          block.call
        else
          tenant = TenancyDable.configuration.tenant_class.find_by(id: tenant_id)
          TenancyDable.with_tenant(tenant) do
            membership_id = job.tenancy_dable_membership_id
            if membership_id
              TenancyDable.current_membership =
                TenancyDable.configuration.membership_class.find_by(id: membership_id)
            end
            block.call
          end
        end
      end
    end

    # The tenant id and membership id captured at enqueue and restored at perform.
    # `serialize` reads them from the live context on the way out; `deserialize`
    # reads them from the payload on the way back in; `around_perform` consumes them.
    attr_accessor :tenancy_dable_tenant_id, :tenancy_dable_membership_id

    # Snapshot the current tenant id AND membership id into the serialized payload.
    # ActiveJob calls `serialize` at enqueue, so this captures the workspace — and
    # the role within it — the job was enqueued under. Already-set ids (e.g. a
    # retry re-serializing after restore) are kept.
    def serialize
      super.merge(
        SERIALIZED_TENANT_KEY => tenancy_dable_tenant_id || TenancyDable.current_tenant&.id,
        SERIALIZED_MEMBERSHIP_KEY => tenancy_dable_membership_id || TenancyDable.current_membership&.id
      )
    end

    # Read the captured tenant id and membership id back out of the payload in the
    # worker. ActiveJob calls `deserialize` before `perform`; `around_perform` then
    # restores them. An older payload without the membership key yields nil.
    def deserialize(job_data)
      super
      self.tenancy_dable_tenant_id = job_data[SERIALIZED_TENANT_KEY]
      self.tenancy_dable_membership_id = job_data[SERIALIZED_MEMBERSHIP_KEY]
    end
  end
end
