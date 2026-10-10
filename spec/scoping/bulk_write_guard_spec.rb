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

  context "with the tenant filter removed or widened (shared classifier, §16.1)" do
    it "refuses a bulk write after unscope(where: :tenant_id)" do
      create(:widget, tenant: tenant_b)
      TenancyDable.current_tenant = tenant_a

      expect { Widget.unscope(where: :tenant_id).delete_all }
        .to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.count).to eq(1)
    end

    it "refuses a bulk write on a multi-tenant IN list that contains the current tenant" do
      create(:widget, tenant: tenant_b)
      TenancyDable.current_tenant = tenant_a

      expect { Widget.where(tenant_id: [tenant_a.id, tenant_b.id]).delete_all }
        .to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.count).to eq(1)
    end

    it "allows a bulk write after rewhere(tenant_id: current)" do
      mine = create(:widget, tenant: tenant_a)
      TenancyDable.current_tenant = tenant_a

      expect { Widget.rewhere(tenant_id: tenant_a.id).update_all(name: "renamed") }.not_to raise_error
      expect(mine.reload.name).to eq("renamed")
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

  context "update_all that rewrites the tenant fk (invariant 3)" do
    let!(:mine) { create(:widget, tenant: tenant_b, name: "B-1") }

    def tenant_of(record)
      TenancyDable.without_tenant { Widget.find(record.id).tenant_id }
    end

    it "raises TenantImmutableError for a Symbol key and moves nothing" do
      expect { TenancyDable.with_tenant(tenant_b) { Widget.where(id: mine.id).update_all(tenant_id: tenant_a.id) } }
        .to raise_error(TenancyDable::TenantImmutableError, /Widget#tenant_id is immutable/)
      expect(tenant_of(mine)).to eq(tenant_b.id)
    end

    it "raises TenantImmutableError for a String key" do
      expect { TenancyDable.with_tenant(tenant_b) { Widget.update_all("tenant_id" => tenant_a.id) } }
        .to raise_error(TenancyDable::TenantImmutableError)
      expect(tenant_of(mine)).to eq(tenant_b.id)
    end

    it "raises even when the value is the current tenant's own id" do
      expect { TenancyDable.with_tenant(tenant_b) { Widget.update_all(tenant_id: tenant_b.id) } }
        .to raise_error(TenancyDable::TenantImmutableError)
    end

    it "allows the rewrite inside without_tenant" do
      TenancyDable.with_tenant(tenant_b) do
        TenancyDable.without_tenant { Widget.where(id: mine.id).update_all(tenant_id: tenant_a.id) }
      end
      expect(tenant_of(mine)).to eq(tenant_a.id)
    end

    it "allows an update_all on other columns" do
      TenancyDable.with_tenant(tenant_b) { Widget.update_all(name: "renamed") }
      expect(mine.reload.name).to eq("renamed")
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

  describe "the classifier on literal pins" do
    it "writes through where(tenant_id: [b, b]) and refuses a list holding another tenant" do
      mine = create(:widget, tenant: tenant_b, name: "mine")
      create(:widget, tenant: tenant_a, name: "theirs")

      TenancyDable.with_tenant(tenant_b) { Widget.where(tenant_id: [tenant_b.id, tenant_b.id]).update_all(name: "renamed") }
      expect(mine.reload.name).to eq("renamed")

      expect { TenancyDable.with_tenant(tenant_b) { Widget.unscoped.where(tenant_id: [tenant_b.id, tenant_a.id]).delete_all } }
        .to raise_error(TenancyDable::BulkWriteError)
    end

    it "refuses an Arel equality on the fk against a subquery" do
      subquery = Tenant.where(id: tenant_a.id).select(:id).arel
      create(:widget, tenant: tenant_a, name: "theirs")

      expect { TenancyDable.with_tenant(tenant_b) { Widget.unscoped.where(Widget.arel_table[:tenant_id].eq(subquery)).delete_all } }
        .to raise_error(TenancyDable::BulkWriteError)
      expect(Widget.unscoped.where(name: "theirs").count).to eq(1)
    end
  end
end
