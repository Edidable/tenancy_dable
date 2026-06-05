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
  # OPT-IN: this file is deliberately NOT required by the gem entry point, so
  # ActiveJob stays an OPTIONAL dependency — a host wires it up only if it runs
  # jobs (`require "tenancy_dable/job"`). The including class must be an
  # `ActiveJob::Base` subclass; the concern uses `around_perform` / `serialize` /
  # `deserialize`, which that base provides.
  module Job
    extend ActiveSupport::Concern

    # The payload key the tenant id travels in. Namespaced so it can never collide
    # with a host's own serialized job arguments.
    SERIALIZED_TENANT_KEY = "tenancy_dable_tenant_id"

    included do
      # Restore the enqueue-time tenant for the whole of `perform`, then tear it
      # back down (via `with_tenant`'s ensure) so a pooled worker thread never
      # leaks one job's tenant into the next. A nil id — a job enqueued with no
      # current tenant — performs untouched (fail-open, mirroring the default
      # scope). The tenant is re-loaded by id so `perform` gets a live record.
      around_perform do |job, block|
        tenant_id = job.tenancy_dable_tenant_id
        if tenant_id.nil?
          block.call
        else
          tenant = TenancyDable.configuration.tenant_class.find_by(id: tenant_id)
          TenancyDable.with_tenant(tenant) { block.call }
        end
      end
    end

    # The tenant id captured at enqueue and restored at perform. `serialize` reads
    # it from the live context on the way out; `deserialize` reads it from the
    # payload on the way back in; `around_perform` consumes it.
    attr_accessor :tenancy_dable_tenant_id

    # Snapshot the current tenant id into the serialized payload. ActiveJob calls
    # `serialize` at enqueue, so this captures the workspace the job was enqueued
    # under. An already-set id (e.g. a retry re-serializing after restore) is kept.
    def serialize
      super.merge(SERIALIZED_TENANT_KEY => tenancy_dable_tenant_id || TenancyDable.current_tenant&.id)
    end

    # Read the captured tenant id back out of the payload in the worker. ActiveJob
    # calls `deserialize` before `perform`; `around_perform` then restores it.
    def deserialize(job_data)
      super
      self.tenancy_dable_tenant_id = job_data[SERIALIZED_TENANT_KEY]
    end
  end
end
