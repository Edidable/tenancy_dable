# frozen_string_literal: true

require "rails_helper"
require "async"

# §16.4: the context carrier.
RSpec.describe TenancyDable::Snapshot do
  let(:tenant) { create(:tenant) }
  let(:other) { create(:tenant) }
  let(:membership) { create(:membership, tenant: tenant) }
  let(:foreign_membership) { create(:membership, tenant: other) }

  def raw_state
    [TenancyDable::Current.tenant, TenancyDable::Current.membership, TenancyDable::Current.tenant_scope_disabled]
  end

  describe "TenancyDable.snapshot" do
    it "captures the raw stored state" do
      TenancyDable.current_tenant = tenant
      TenancyDable.current_membership = membership
      snap = TenancyDable.without_tenant { TenancyDable.snapshot }
      expect(snap).to have_attributes(tenant: tenant, membership: membership, tenant_scope_disabled: true)
    end

    it "captures a foreign membership as set, not the reader's nil" do
      TenancyDable.current_tenant = tenant
      TenancyDable.current_membership = foreign_membership
      expect(TenancyDable.snapshot.membership).to eq(foreign_membership)
    end

    it "is all nil on a clean thread" do
      expect(TenancyDable.snapshot).to have_attributes(tenant: nil, membership: nil, tenant_scope_disabled: nil)
    end
  end

  describe "#restore" do
    let(:snap) { described_class.new(tenant: tenant, membership: membership, tenant_scope_disabled: true) }

    it "establishes the state inside and returns the block's value" do
      inside = nil
      result = snap.restore do
        inside = raw_state
        :value
      end
      expect(result).to eq(:value)
      expect(inside).to eq([tenant, membership, true])
    end

    it "resets to nil/nil/nil on normal exit" do
      snap.restore {}
      expect(raw_state).to eq([nil, nil, nil])
    end

    it "resets on raise and re-raises" do
      expect { snap.restore { raise "boom" } }.to raise_error("boom")
      expect(raw_state).to eq([nil, nil, nil])
    end

    it "puts back the restoring thread's own prior state" do
      TenancyDable.current_tenant = tenant
      TenancyDable.current_membership = membership
      described_class.new(tenant: tenant, membership: nil, tenant_scope_disabled: true).restore {}
      expect(raw_state).to eq([tenant, membership, nil])
    end

    it "treats restoring into a different tenant as a switch (audit override applies)" do
      TenancyDable.configuration.audit_overrides = :raise
      TenancyDable.current_tenant = other
      expect { snap.restore {} }.to raise_error(TenancyDable::TenantOverrideError)
    end

    it "fires the RLS statement on entry and on restore" do
      statements = []
      TenancyDable.configuration.rls = true
      TenancyDable.configuration.rls_statement = ->(t) {
        statements << t&.id
        nil
      }
      snap.restore {}
      expect(statements).to eq([tenant.id, nil])
    end

    it "answers a nil current_membership when the carried membership is another tenant's" do
      foreign = described_class.new(tenant: tenant, membership: foreign_membership, tenant_scope_disabled: nil)
      inside = nil
      foreign.restore { inside = [TenancyDable.current_membership, TenancyDable.foreign_membership?] }
      expect(inside).to eq([nil, true])
    end

    it "restores the flag of a snapshot taken in without_tenant with no event and no reason check" do
      TenancyDable.configuration.require_bypass_reason = true
      snap = TenancyDable.without_tenant(reason: "x") { TenancyDable.snapshot }
      events = []
      sub = ActiveSupport::Notifications.subscribe(TenancyDable::WITHOUT_TENANT_EVENT) { |*a| events << a }
      begin
        flag = nil
        expect { snap.restore { flag = TenancyDable::Current.tenant_scope_disabled } }.not_to raise_error
        expect(flag).to be(true)
        expect(events).to be_empty
      ensure
        ActiveSupport::Notifications.unsubscribe(sub)
      end
    end

    it "raises LocalJumpError without a block" do
      expect { snap.restore }.to raise_error(LocalJumpError)
    end
  end

  describe "across threads and fibers" do
    it "carries the state into Thread.new and leaves the thread's own state clean" do
      TenancyDable.current_tenant = tenant
      TenancyDable.current_membership = membership
      snap = TenancyDable.snapshot

      thread_seen = Thread.new do
        before = [TenancyDable::Current.tenant]
        inside = snap.restore { [TenancyDable::Current.tenant, TenancyDable::Current.membership] }
        [before, inside, TenancyDable::Current.tenant]
      end.value

      expect(thread_seen).to eq([[nil], [tenant, membership], nil])
    end

    it "starts a plain thread with no tenant (fail closed)" do
      TenancyDable.current_tenant = tenant
      expect(Thread.new { TenancyDable.current_tenant }.value).to be_nil
    end

    it "carries into a thread through Thread.new(&carry)" do
      TenancyDable.current_tenant = tenant
      expect(Thread.new(&TenancyDable.carry { TenancyDable.current_tenant }).value).to eq(tenant)
    end

    it "carries into an Async task under :fiber isolation" do
      TenancyDable.current_tenant = tenant
      snap = TenancyDable.snapshot
      level = ActiveSupport::IsolatedExecutionState.isolation_level
      seen = nil
      begin
        ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
        Sync do
          seen = Async { snap.restore { TenancyDable::Current.tenant } }.wait
        end
      ensure
        ActiveSupport::IsolatedExecutionState.isolation_level = level
      end
      expect(seen).to eq(tenant)
    end
  end

  describe "TenancyDable.carry" do
    it "forwards positional and keyword arguments and returns the value" do
      TenancyDable.current_tenant = tenant
      carried = TenancyDable.carry { |a, b = 2, k: 0| [a, b, k, TenancyDable::Current.tenant] }
      TenancyDable::Current.reset
      expect(carried.call(1, k: 3)).to eq([1, 2, 3, tenant])
    end

    it "snapshots at carry time, not at call time" do
      TenancyDable.current_tenant = tenant
      carried = TenancyDable.carry { TenancyDable::Current.tenant }
      TenancyDable::Current.reset
      TenancyDable.current_tenant = other
      expect(carried.call).to eq(tenant)
    end

    it "returns a lambda" do
      expect(TenancyDable.carry {}).to be_lambda
    end

    it "raises LocalJumpError without a block" do
      expect { TenancyDable.carry }.to raise_error(LocalJumpError)
    end
  end
end
