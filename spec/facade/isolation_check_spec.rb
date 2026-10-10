# frozen_string_literal: true

require "rails_helper"
require "async"

# §16.4: the isolation check runs first in every gem write to Current.
RSpec.describe "TenancyDable isolation check" do
  let(:tenant) { create(:tenant) }
  let(:membership) { create(:membership, tenant: tenant) }
  let(:message) { /fiber scheduler with thread isolation.*isolation_level = :fiber/ }
  let(:logger) { instance_double(Logger, warn: nil) }

  def under_scheduler(level)
    allow(Fiber).to receive(:scheduler).and_return(Object.new)
    allow(ActiveSupport::IsolatedExecutionState).to receive(:isolation_level).and_return(level)
  end

  # The three gem writers, each as a callable.
  let(:writers) do
    {
      "current_tenant=" => -> { TenancyDable.current_tenant = tenant },
      "current_membership=" => -> { TenancyDable.current_membership = membership },
      "with_tenant" => -> { TenancyDable.with_tenant(tenant) {} },
      "without_tenant" => -> { TenancyDable.without_tenant {} },
      "Snapshot#restore" => -> { TenancyDable.snapshot.restore {} }
    }
  end

  %w[current_tenant= current_membership= with_tenant without_tenant Snapshot#restore].each do |name|
    describe name do
      it "raises UnsafeIsolationError under a scheduler with thread isolation (default :raise)" do
        under_scheduler(:thread)
        expect { writers[name].call }.to raise_error(TenancyDable::UnsafeIsolationError, message)
      end

      it "writes nothing when it raises" do
        under_scheduler(:thread)
        begin
          writers[name].call
        rescue TenancyDable::UnsafeIsolationError
          nil
        end
        expect(TenancyDable::Current.tenant).to be_nil
        expect(TenancyDable::Current.membership).to be_nil
        expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
      end

      it "logs and proceeds under :warn, on every detected write" do
        under_scheduler(:thread)
        TenancyDable.configuration.isolation_check = :warn
        allow(Rails).to receive(:logger).and_return(logger)
        expect { writers[name].call }.not_to raise_error
        expect(logger).to have_received(:warn).with(/\[TenancyDable\] .*fiber scheduler with thread isolation/).at_least(:once)
      end

      it "does not evaluate anything under :off" do
        TenancyDable.configuration.isolation_check = :off
        expect(Fiber).not_to receive(:scheduler)
        expect { writers[name].call }.not_to raise_error
      end

      it "passes with no scheduler on the thread" do
        allow(Fiber).to receive(:scheduler).and_return(nil)
        allow(ActiveSupport::IsolatedExecutionState).to receive(:isolation_level).and_return(:thread)
        expect { writers[name].call }.not_to raise_error
      end

      it "passes under a scheduler with :fiber isolation" do
        under_scheduler(:fiber)
        expect { writers[name].call }.not_to raise_error
      end
    end
  end

  it "carries no ids in the message" do
    under_scheduler(:thread)
    expect { TenancyDable.current_tenant = tenant }
      .to raise_error(TenancyDable::UnsafeIsolationError) { |e| expect(e.message).not_to match(/\d/) }
  end

  it "descends from TenancyDable::Error" do
    expect(TenancyDable::UnsafeIsolationError.ancestors).to include(TenancyDable::Error)
  end

  describe "with a real Async reactor" do
    # Records are built (lazy lets forced) before the reactor and the level toggle:
    # a query from a fiber or while toggled would use its own connection, outside
    # the example's transaction.
    before { tenant }

    it "raises under thread isolation" do
      # Rescued inside the task so Async does not log the expected failure.
      error = Async do
        TenancyDable.current_tenant = tenant
        nil
      rescue TenancyDable::UnsafeIsolationError => e
        e
      end.wait
      expect(error).to be_a(TenancyDable::UnsafeIsolationError)
      expect(error.message).to match(message)
    end

    it "passes under :fiber isolation, each fiber keeping its own tenant" do
      tenant_b = create(:tenant)
      level = ActiveSupport::IsolatedExecutionState.isolation_level
      seen = []
      begin
        ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
        Sync do
          [tenant, tenant_b].map { |t|
            Async do |task|
              TenancyDable.current_tenant = t
              task.yield
              seen << TenancyDable.current_tenant&.id
            end
          }.each(&:wait)
        end
      ensure
        ActiveSupport::IsolatedExecutionState.isolation_level = level
      end
      expect(seen).to contain_exactly(tenant.id, tenant_b.id)
    end
  end
end
