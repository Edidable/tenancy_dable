# frozen_string_literal: true

require "rails_helper"

# Creating into another tenant is refused (DESIGN.md §16.2). Inside
# `with_tenant(b)`, a new record whose fk names tenant A raises
# CrossTenantWriteError, on every path that can write it and whatever validators
# the model has (Widget validates uniqueness, Gadget has none), never the read
# error, and nothing is written. The same rule for a persisted record in hand
# lives in foreign_record_write_spec.rb, and for insert_all in insert_all_guard_spec.rb.
RSpec.describe "TenancyDable::Scoped — create refusal" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  def acting_in_b(&block) = TenancyDable.with_tenant(tenant_b, &block)

  def written_rows = TenancyDable.without_tenant { Widget.count + Gadget.count }

  describe "a foreign fk while acting in another tenant" do
    before { tenant_a && tenant_b }

    it "refuses a.widgets.create!" do
      expect { acting_in_b { tenant_a.widgets.create!(name: "x") } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(written_rows).to eq(0)
    end

    it "refuses Widget.create!(tenant: a)" do
      expect { acting_in_b { Widget.create!(name: "x", tenant: tenant_a) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(written_rows).to eq(0)
    end

    it "refuses Gadget.create!(tenant_id: a.id) on a model with no uniqueness validation" do
      expect { acting_in_b { Gadget.create!(name: "x", tenant_id: tenant_a.id) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(written_rows).to eq(0)
    end

    it "refuses save(validate: false)" do
      gadget = Gadget.new(name: "x", tenant_id: tenant_a.id)

      expect { acting_in_b { gadget.save(validate: false) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(written_rows).to eq(0)
    end

    it "refuses valid? on a new record (fail fast)" do
      widget = Widget.new(name: "x", tenant_id: tenant_a.id)

      expect { acting_in_b { widget.valid? } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "never raises the read error, even with a uniqueness validation that would read" do
      create(:widget, tenant: tenant_a, name: "taken")

      expect { acting_in_b { Widget.create!(name: "taken", tenant: tenant_a) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "carries model name and tenant ids only" do
      expect { acting_in_b { Gadget.create!(name: "secret", tenant_id: tenant_a.id) } }
        .to raise_error(TenancyDable::CrossTenantWriteError) { |error|
          expect(error.message).to eq(
            "refusing to create Gadget in tenant ##{tenant_a.id} while acting in " \
            "tenant ##{tenant_b.id}; enter the tenant with TenancyDable.with_tenant"
          )
        }
    end

    it "refuses a new record with a foreign fk on every save path, valid or not" do
      widget = Widget.new(name: "x", tenant_id: tenant_a.id)

      expect { acting_in_b { widget.save } }.to raise_error(TenancyDable::CrossTenantWriteError)
      expect(written_rows).to eq(0)
    end

    it "descends from TenancyDable::Error" do
      expect(TenancyDable::CrossTenantWriteError.ancestors).to include(TenancyDable::Error)
    end
  end

  describe "what persists as in 0.4.0" do
    it "the current tenant's explicit fk" do
      widget = acting_in_b { Widget.create!(name: "x", tenant_id: tenant_b.id) }

      expect(widget).to be_persisted
      expect(widget.tenant_id).to eq(tenant_b.id)
    end

    it "a blank fk, auto-assigned from the current tenant" do
      widget = acting_in_b { Widget.create!(name: "x") }

      expect(widget.tenant_id).to eq(tenant_b.id)
    end

    it "any fk when there is no current tenant" do
      widget = Widget.create!(name: "x", tenant_id: tenant_a.id)

      expect(widget).to be_persisted
    end

    it "any fk inside without_tenant" do
      widget = acting_in_b { TenancyDable.without_tenant { Widget.create!(name: "x", tenant_id: tenant_a.id) } }

      expect(widget.tenant_id).to eq(tenant_a.id)
    end

    it "a foreign fk inside the target tenant's own with_tenant" do
      widget = TenancyDable.with_tenant(tenant_a) { Widget.create!(name: "x", tenant_id: tenant_a.id) }

      expect(widget.tenant_id).to eq(tenant_a.id)
    end
  end
end
