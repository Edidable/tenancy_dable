# frozen_string_literal: true

require "rails_helper"
require "active_job"
require "tenancy_dable/job"

# A NAMED job (not an anonymous Class.new) so ActiveJob can serialize it by class
# name and `execute` can constantize it back across the queue boundary. It records
# what it observed DURING perform into class-level sinks, because
# ActiveSupport::CurrentAttributes is cleared the instant perform returns — the
# sinks are the only channel to observe the in-flight tenant from the example.
class IntegrationTenantProbeJob < ActiveJob::Base
  include TenancyDable::Job

  class << self
    attr_accessor :observed_tenant_id, :observed_membership_id, :observed_widget_ids
  end

  def perform
    self.class.observed_tenant_id = TenancyDable.current_tenant&.id
    self.class.observed_membership_id = TenancyDable.current_membership&.id
    self.class.observed_widget_ids = Widget.order(:id).pluck(:id)
  end
end

# ActiveJob tenant propagation (DESIGN §10-I; PLAN mission "ActiveJob tenant
# propagation"). `TenancyDable::Job` captures the enqueue-time tenant into the
# serialized payload and restores it as `current_tenant` for the worker's
# `perform`, so a background job scopes exactly like the request that enqueued it.
# The serialize → execute pairing below IS the serialize/deserialize round-trip
# the contract names, asserted adapter-independently.
RSpec.describe "Integration: ActiveJob tenant propagation" do
  let(:tenant_a) { create(:tenant, slug: "alpha") }
  let(:tenant_b) { create(:tenant, slug: "bravo") }
  let(:user) { create(:user) }
  let(:membership_a) { create(:membership, user: user, tenant: tenant_a) }

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    previous_logger = ActiveJob::Base.logger
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.logger = ActiveSupport::Logger.new(IO::NULL)
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous_adapter
    ActiveJob::Base.logger = previous_logger
  end

  before do
    IntegrationTenantProbeJob.observed_tenant_id = nil
    IntegrationTenantProbeJob.observed_membership_id = nil
    IntegrationTenantProbeJob.observed_widget_ids = nil
  end

  it "captures the enqueue-time tenant id into the serialized payload" do
    payload = TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.new.serialize }

    expect(payload["tenancy_dable_tenant_id"]).to eq(tenant_a.id)
  end

  it "restores that tenant on perform, in a worker context that had none" do
    payload = TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.new.serialize }

    # Nothing ambient — restoration must come from the payload, not leftover state.
    expect(TenancyDable.current_tenant).to be_nil
    ActiveJob::Base.execute(payload)

    expect(IntegrationTenantProbeJob.observed_tenant_id).to eq(tenant_a.id)
  end

  it "scopes the job's own queries to the restored tenant" do
    a1 = create(:widget, tenant: tenant_a, name: "A-1")
    a2 = create(:widget, tenant: tenant_a, name: "A-2")
    _b1 = create(:widget, tenant: tenant_b, name: "B-1")
    payload = TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.new.serialize }

    ActiveJob::Base.execute(payload)

    # The Widget query INSIDE perform saw A's rows only — propagation drives the
    # scoping engine end-to-end, not just a stored id.
    expect(IntegrationTenantProbeJob.observed_widget_ids).to contain_exactly(a1.id, a2.id)
  end

  it "leaves no tenant set after the job finishes (no cross-job leak)" do
    payload = TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.new.serialize }

    ActiveJob::Base.execute(payload)

    expect(TenancyDable.current_tenant).to be_nil
  end

  it "round-trips a nil tenant when enqueued with no current tenant (fail-open)" do
    expect(TenancyDable.current_tenant).to be_nil
    payload = IntegrationTenantProbeJob.new.serialize
    expect(payload["tenancy_dable_tenant_id"]).to be_nil

    expect { ActiveJob::Base.execute(payload) }.not_to raise_error
    expect(IntegrationTenantProbeJob.observed_tenant_id).to be_nil
  end

  it "carries the tenant through the realistic perform_later enqueue path" do
    TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.perform_later }

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
    expect(enqueued.size).to eq(1)
    expect(enqueued.first["tenancy_dable_tenant_id"]).to eq(tenant_a.id)

    # Drain OUTSIDE A's context — the worker restores A purely from the payload.
    expect(TenancyDable.current_tenant).to be_nil
    ActiveJob::Base.execute(enqueued.first)

    expect(IntegrationTenantProbeJob.observed_tenant_id).to eq(tenant_a.id)
  end

  # v0.3.0: the membership rides the same payload as the tenant, so a job's
  # context — workspace AND role — matches the request that enqueued it. The
  # membership id is captured alongside the tenant id, reloaded by id in the
  # worker, and set as `current_membership` for `perform`'s duration only.
  describe "membership propagation" do
    # Snapshot a job enqueued with BOTH a current tenant and membership — the
    # state Resolvable establishes for every authenticated request.
    def enqueue_with_membership
      TenancyDable.with_tenant(tenant_a) do
        TenancyDable.current_membership = membership_a
        IntegrationTenantProbeJob.new.serialize
      end
    end

    it "captures the enqueue-time membership id into the serialized payload" do
      payload = enqueue_with_membership

      expect(payload["tenancy_dable_membership_id"]).to eq(membership_a.id)
      expect(payload["tenancy_dable_tenant_id"]).to eq(tenant_a.id)
    end

    it "restores BOTH the tenant and the membership on perform" do
      payload = enqueue_with_membership

      # Nothing ambient — restoration must come from the payload, not leftovers.
      expect(TenancyDable.current_tenant).to be_nil
      expect(TenancyDable.current_membership).to be_nil
      ActiveJob::Base.execute(payload)

      expect(IntegrationTenantProbeJob.observed_tenant_id).to eq(tenant_a.id)
      expect(IntegrationTenantProbeJob.observed_membership_id).to eq(membership_a.id)
    end

    it "leaves no membership set after the job finishes (no cross-job leak)" do
      payload = enqueue_with_membership

      ActiveJob::Base.execute(payload)

      expect(TenancyDable.current_tenant).to be_nil
      expect(TenancyDable.current_membership).to be_nil
    end

    it "restores the tenant but a nil membership for an older payload (no membership key)" do
      # A pre-v0.3.0 enqueue carries the tenant id but no membership key at all.
      payload = TenancyDable.with_tenant(tenant_a) { IntegrationTenantProbeJob.new.serialize }
      payload.delete("tenancy_dable_membership_id")
      expect(payload).not_to have_key("tenancy_dable_membership_id")

      expect { ActiveJob::Base.execute(payload) }.not_to raise_error

      # Tenant propagation is unchanged; the absent membership restores as nil.
      expect(IntegrationTenantProbeJob.observed_tenant_id).to eq(tenant_a.id)
      expect(IntegrationTenantProbeJob.observed_membership_id).to be_nil
    end
  end
end
