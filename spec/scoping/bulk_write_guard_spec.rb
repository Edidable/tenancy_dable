# frozen_string_literal: true

require "rails_helper"

# Bulk-write guard, prepended to ActiveRecord::Relation (DESIGN.md §5.2).
# update_all / delete_all / destroy_all skip the default scope's WHERE, so the
# guard refuses any bulk write on a tenant-scoped relation that is not provably
# pinned to the current tenant. Each example also asserts NO rows changed, so a
# regression that lets the write through (instead of raising) still fails.
RSpec.describe "TenancyDable::RelationExtension — bulk-write guard" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  context "with no current tenant" do
    it "raises BulkWriteError on update_all and writes nothing" do
      create(:widget, tenant: tenant_a)

      expect { Widget.update_all(name: "hacked") }
        .to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.where(name: "hacked")).to be_empty
    end

    it "raises BulkWriteError on delete_all and deletes nothing" do
      create(:widget, tenant: tenant_a)
      create(:widget, tenant: tenant_b)

      expect { Widget.delete_all }.to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.count).to eq(2)
    end

    it "raises BulkWriteError on destroy_all and destroys nothing" do
      create(:widget, tenant: tenant_a)
      create(:widget, tenant: tenant_b)

      expect { Widget.destroy_all }.to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.count).to eq(2)
    end
  end

  context "with a current tenant" do
    it "raises BulkWriteError when the relation targets a different tenant" do
      create(:widget, tenant: tenant_b)
      TenancyDable.current_tenant = tenant_a

      expect { Widget.where(tenant_id: tenant_b.id).delete_all }
        .to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.count).to eq(1)
    end

    it "allows a bulk write pinned to the current tenant" do
      mine = create(:widget, tenant: tenant_a)
      theirs = create(:widget, tenant: tenant_b)
      TenancyDable.current_tenant = tenant_a

      expect { Widget.update_all(name: "renamed") }.not_to raise_error

      expect(mine.reload.name).to eq("renamed")
      expect(theirs.reload.name).not_to eq("renamed") # the other tenant is untouched
    end
  end

  context "inside without_tenant" do
    it "allows an otherwise-guarded bulk write across all tenants" do
      create(:widget, tenant: tenant_a)
      create(:widget, tenant: tenant_b)

      TenancyDable.without_tenant do
        expect { Widget.update_all(name: "bulk") }.not_to raise_error
      end

      expect(Widget.unscoped.where(name: "bulk").count).to eq(2)
    end
  end

  it "leaves non-tenant-scoped models untouched by the guard" do
    # Tenant is not tenant-scoped (it IS the tenant), so its bulk writes pass
    # straight through even with no current tenant.
    create(:tenant, name: "Before")

    expect { Tenant.where(name: "Before").update_all(name: "After") }
      .not_to raise_error
    expect(Tenant.where(name: "After")).to be_present
  end
end
