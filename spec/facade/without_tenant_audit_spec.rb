# frozen_string_literal: true

require "rails_helper"

# §16.5: the audited without_tenant.
RSpec.describe "TenancyDable.without_tenant audit" do
  let(:tenant) { create(:tenant) }
  let(:events) { [] }

  around do |example|
    sub = ActiveSupport::Notifications.subscribe(TenancyDable::WITHOUT_TENANT_EVENT) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    example.run
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "emits the event with exactly reason, tenant_id and call_site" do
    TenancyDable.current_tenant = tenant
    TenancyDable.without_tenant(reason: "nightly rollup") {}
    expect(events.size).to eq(1)
    expect(events.first.payload.keys).to contain_exactly(:reason, :tenant_id, :call_site)
    expect(events.first.payload).to include(reason: "nightly rollup", tenant_id: tenant.id)
  end

  it "reports a nil reason and nil tenant_id when omitted" do
    TenancyDable.without_tenant {}
    expect(events.first.payload).to include(reason: nil, tenant_id: nil)
  end

  it "points call_site at the file and line that called without_tenant, not the gem" do
    line = __LINE__ + 1
    TenancyDable.without_tenant(reason: "x") {}
    expect(events.first.payload[:call_site]).to eq("#{__FILE__}:#{line}")
  end

  it "returns the block's value and sets the flag inside" do
    flag = nil
    result = TenancyDable.without_tenant(reason: "x") do
      flag = TenancyDable::Current.tenant_scope_disabled
      :done
    end
    expect(result).to eq(:done)
    expect(flag).to be(true)
    expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
  end

  it "emits the payload without a block, so a raising block adds no exception keys" do
    expect { TenancyDable.without_tenant(reason: "x") { raise ActiveRecord::RecordInvalid } }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(events.first.payload.keys).to contain_exactly(:reason, :tenant_id, :call_site)
  end

  it "never lets a subscriber failure start the bypass (fail closed)" do
    ran = false
    sub = ActiveSupport::Notifications.subscribe(TenancyDable::WITHOUT_TENANT_EVENT) { raise "subscriber" }
    begin
      expect { TenancyDable.without_tenant(reason: "x") { ran = true } }.to raise_error("subscriber")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
    expect(ran).to be(false)
    expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
  end

  describe "config.require_bypass_reason" do
    it "accepts a blank reason by default" do
      expect { TenancyDable.without_tenant {} }.not_to raise_error
    end

    context "when on" do
      before { TenancyDable.configuration.require_bypass_reason = true }

      [nil, "", "   "].each do |blank|
        it "raises BypassReasonError for #{blank.inspect}, with no event and no state change" do
          flag = :untouched
          expect { TenancyDable.without_tenant(reason: blank) { flag = :ran } }
            .to raise_error(TenancyDable::BypassReasonError, /non-blank reason/)
          expect(flag).to eq(:untouched)
          expect(events).to be_empty
          expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
        end
      end

      it "accepts a real reason" do
        expect(TenancyDable.without_tenant(reason: "backfill") { 1 }).to eq(1)
      end
    end

    [Object.new, 42, ["why"], {why: 1}, 1.5, true].each do |bad|
      it "raises BypassReasonError for a #{bad.class} reason, before any event or state change" do
        flag = :untouched
        expect { TenancyDable.without_tenant(reason: bad) { flag = :ran } }
          .to raise_error(TenancyDable::BypassReasonError, /String or a Symbol/)
        expect(flag).to eq(:untouched)
        expect(events).to be_empty
        expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
      end
    end

    it "accepts a Symbol reason" do
      expect(TenancyDable.without_tenant(reason: :backfill) { 1 }).to eq(1)
    end

    it "makes BypassReasonError a TenancyDable::Error" do
      expect(TenancyDable::BypassReasonError.ancestors).to include(TenancyDable::Error)
    end
  end

  describe "nesting" do
    it "reports each level with its own call site and the same tenant_id" do
      TenancyDable.current_tenant = tenant
      TenancyDable.without_tenant(reason: "outer") do
        TenancyDable.without_tenant(reason: "inner") {}
      end
      expect(events.map { |e| e.payload[:reason] }).to eq(%w[inner outer].reverse)
      expect(events.map { |e| e.payload[:tenant_id] }.uniq).to eq([tenant.id])
      expect(events.map { |e| e.payload[:call_site] }.uniq.size).to eq(2)
    end

    it "restores the prior flag at each level on normal exit" do
      seen = []
      TenancyDable.without_tenant(reason: "outer") do
        TenancyDable.without_tenant(reason: "inner") {}
        seen << TenancyDable::Current.tenant_scope_disabled
      end
      seen << TenancyDable::Current.tenant_scope_disabled
      expect(seen).to eq([true, nil])
    end

    it "restores the prior flag at each level on raise" do
      seen = nil
      TenancyDable.without_tenant(reason: "outer") do
        TenancyDable.without_tenant(reason: "inner") { raise "boom" }
      rescue
        seen = TenancyDable::Current.tenant_scope_disabled
      end
      expect(seen).to be(true)
      expect(TenancyDable::Current.tenant_scope_disabled).to be_nil
    end
  end

  it "puts no record in the payload when the block raises" do
    record = build(:widget, tenant: tenant)
    expect { TenancyDable.without_tenant(reason: "x") { raise ActiveRecord::RecordInvalid, record } }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(events.first.payload.values.grep(ActiveRecord::Base)).to be_empty
  end
end

RSpec.describe "TenancyDable.without_tenant with no subscriber" do
  it "computes neither the event nor the call site" do
    allow(TenancyDable).to receive(:call_site).and_call_original
    allow(ActiveSupport::Notifications).to receive(:instrument).and_call_original
    expect(ActiveSupport::Notifications.notifier.listening?(TenancyDable::WITHOUT_TENANT_EVENT)).to be(false)
    TenancyDable.without_tenant(reason: "x") {}
    expect(TenancyDable).not_to have_received(:call_site)
    expect(ActiveSupport::Notifications).not_to have_received(:instrument).with(TenancyDable::WITHOUT_TENANT_EVENT, anything)
  end
end
