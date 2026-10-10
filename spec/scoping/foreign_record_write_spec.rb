# frozen_string_literal: true

require "rails_helper"

# A persisted record of another tenant, still in hand while acting in B, is
# refused like a create (DESIGN.md §16.2): update, destroy, touch, delete and
# update_columns raise CrossTenantWriteError and nothing is written. The tenant
# fk cannot be rewritten through update_column(s) at all.
RSpec.describe "TenancyDable::Scoped — writes to a record of another tenant" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let!(:gadget_a) { create(:gadget, tenant: tenant_a, name: "GA-1") }
  let(:in_hand) { TenancyDable.with_tenant(tenant_a) { Gadget.find(gadget_a.id) } }

  def acting_in_b(&block) = TenancyDable.with_tenant(tenant_b, &block)

  def row = TenancyDable.without_tenant { Gadget.find(gadget_a.id).attributes.slice("name", "tenant_id", "updated_at") }

  def refusal(action)
    "refusing to #{action} Gadget of tenant ##{tenant_a.id} while acting in tenant ##{tenant_b.id}; " \
      "enter the tenant with TenancyDable.with_tenant"
  end

  describe "refused while acting in another tenant" do
    before { in_hand && tenant_b }

    it "refuses update!" do
      before = row
      expect { acting_in_b { in_hand.update!(name: "x") } }
        .to raise_error(TenancyDable::CrossTenantWriteError, refusal(:update))
      expect(row).to eq(before)
    end

    it "refuses save(validate: false)" do
      in_hand.name = "x"
      before = row

      expect { acting_in_b { in_hand.save(validate: false) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(row).to eq(before)
    end

    it "refuses valid? on a persisted record (fail fast)" do
      expect { acting_in_b { in_hand.valid? } }.to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "refuses a Widget update before its uniqueness validator reads" do
      widget_a = create(:widget, tenant: tenant_a, name: "taken")
      widget = TenancyDable.with_tenant(tenant_a) { Widget.find(widget_a.id) }

      expect { acting_in_b { widget.update!(name: "other") } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "refuses destroy!" do
      expect { acting_in_b { in_hand.destroy! } }
        .to raise_error(TenancyDable::CrossTenantWriteError, refusal(:destroy))
      expect(TenancyDable.without_tenant { Gadget.exists?(gadget_a.id) }).to be(true)
    end

    it "refuses touch" do
      before = row
      expect { acting_in_b { in_hand.touch(time: before["updated_at"] + 3600) } }
        .to raise_error(TenancyDable::CrossTenantWriteError, refusal(:touch))
      expect(row).to eq(before)
    end

    it "refuses update_columns" do
      before = row
      expect { acting_in_b { in_hand.update_columns(name: "x") } }
        .to raise_error(TenancyDable::CrossTenantWriteError, refusal(:update))
      expect(row).to eq(before)
    end

    it "refuses update_column" do
      before = row
      expect { acting_in_b { in_hand.update_column(:name, "x") } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(row).to eq(before)
    end

    it "refuses delete" do
      expect { acting_in_b { in_hand.delete } }
        .to raise_error(TenancyDable::CrossTenantWriteError, refusal(:delete))
      expect(TenancyDable.without_tenant { Gadget.exists?(gadget_a.id) }).to be(true)
    end

    it "judges by the tenant the row holds, not an unsaved assignment" do
      in_hand.tenant = tenant_b # the association writer; the row still says A

      expect { acting_in_b { in_hand.update!(name: "x") } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
    end
  end

  describe "what persists" do
    it "writes a record of the current tenant" do
      TenancyDable.with_tenant(tenant_a) do
        in_hand.update!(name: "own")
        in_hand.touch
        in_hand.update_columns(name: "own-2")
      end

      expect(row["name"]).to eq("own-2")
    end

    it "destroys and deletes a record of the current tenant" do
      other = create(:gadget, tenant: tenant_a)
      TenancyDable.with_tenant(tenant_a) do
        in_hand.destroy!
        Gadget.find(other.id).delete
      end

      expect(TenancyDable.without_tenant { Gadget.count }).to eq(0)
    end

    it "writes any record when there is no current tenant" do
      in_hand.update!(name: "no-tenant")
      in_hand.touch
      in_hand.update_columns(name: "no-tenant-2")

      expect(row["name"]).to eq("no-tenant-2")
    end

    it "writes any record inside without_tenant" do
      acting_in_b do
        TenancyDable.without_tenant do
          in_hand.update!(name: "bypass")
          in_hand.touch
          in_hand.update_columns(name: "bypass-2")
        end
      end

      expect(row["name"]).to eq("bypass-2")
    end

    it "destroys a record of another tenant inside without_tenant" do
      acting_in_b { TenancyDable.without_tenant { in_hand.destroy! } }

      expect(TenancyDable.without_tenant { Gadget.exists?(gadget_a.id) }).to be(false)
    end
  end

  describe "the tenant fk through update_columns / update_column (F8)" do
    it "raises TenantImmutableError for update_columns with another tenant" do
      expect { TenancyDable.with_tenant(tenant_a) { in_hand.update_columns(tenant_id: tenant_b.id, name: "x") } }
        .to raise_error(TenancyDable::TenantImmutableError)
      expect(row).to include("tenant_id" => tenant_a.id, "name" => "GA-1")
    end

    it "raises TenantImmutableError for update_column with another tenant" do
      expect { TenancyDable.with_tenant(tenant_a) { in_hand.update_column(:tenant_id, tenant_b.id) } }
        .to raise_error(TenancyDable::TenantImmutableError)
      expect(row["tenant_id"]).to eq(tenant_a.id)
    end

    it "raises with a string key, with no tenant and inside without_tenant" do
      expect { in_hand.update_columns("tenant_id" => tenant_b.id) }
        .to raise_error(TenancyDable::TenantImmutableError)
      expect { TenancyDable.without_tenant { in_hand.update_column(:tenant_id, tenant_b.id) } }
        .to raise_error(TenancyDable::TenantImmutableError)
    end

    it "allows update_columns that repeats the same tenant id" do
      TenancyDable.with_tenant(tenant_a) { in_hand.update_columns(tenant_id: tenant_a.id, name: "same") }

      expect(row).to include("tenant_id" => tenant_a.id, "name" => "same")
    end
  end
end
