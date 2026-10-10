# frozen_string_literal: true

require "rails_helper"

# Read guard, prepended to ActiveRecord::Relation (DESIGN.md §16.1). While a
# tenant is current, a read of a tenant-scoped model whose tenant filter is
# pinned to another tenant (or several), or was removed, raises
# CrossTenantReadError. The leaks it closes are measured on 0.4.0: an
# association's relation merges the owner's `tenant_id = <owner>` over the
# default scope's `tenant_id = <current>`.
RSpec.describe "TenancyDable::RelationExtension — read guard" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let!(:widget_a) { create(:widget, tenant: tenant_a, name: "A-1") }
  let!(:widget_a2) { create(:widget, tenant: tenant_a, name: "A-2") }

  def refused(&block)
    expect { TenancyDable.with_tenant(tenant_b, &block) }
      .to raise_error(TenancyDable::CrossTenantReadError, /Widget/)
  end

  describe "reads through another tenant's association (acting in B)" do
    it("refuses to_a") { refused { tenant_a.widgets.to_a } }
    it("refuses first") { refused { tenant_a.widgets.first } }
    it("refuses find") { refused { tenant_a.widgets.find(widget_a.id) } }
    it("refuses find_by") { refused { tenant_a.widgets.find_by(name: "A-1") } }
    it("refuses a where chain") { refused { tenant_a.widgets.where(name: "A-1").to_a } }
    it("refuses count") { refused { tenant_a.widgets.count } }
    it("refuses size") { refused { tenant_a.widgets.size } }
    it("refuses pluck") { refused { tenant_a.widgets.pluck(:name) } }
    it("refuses pick") { refused { tenant_a.widgets.pick(:name) } }
    it("refuses exists?") { refused { tenant_a.widgets.exists? } }
    it("refuses any?") { refused { tenant_a.widgets.any? } }
    it("refuses widget_ids") { refused { tenant_a.widget_ids } }
    it("refuses ids") { refused { tenant_a.widgets.ids } }
    it("refuses find_each") { refused { tenant_a.widgets.find_each { |_| } } }
    it("refuses in_batches") { refused { tenant_a.widgets.in_batches { |_| } } }
    it("refuses a has_one reader") { refused { tenant_a.first_widget } }
    it("refuses load_async") { refused { tenant_a.widgets.load_async.to_a } }
    it("refuses sum") { refused { tenant_a.widgets.sum(:id) } }
    it("refuses a grouped count") { refused { tenant_a.widgets.group(:name).count } }
  end

  describe "relation surgery that drops or replaces the tenant filter (acting in B)" do
    it "refuses rewhere(tenant_id: other)" do
      refused { Widget.rewhere(tenant_id: tenant_a.id).to_a }
    end

    it "refuses merging another tenant's unscoped relation" do
      refused { Widget.all.merge(Widget.unscoped.where(tenant_id: tenant_a.id)).to_a }
    end

    it "refuses unscope(where: :tenant_id)" do
      refused { Widget.unscope(where: :tenant_id).to_a }
    end

    it "refuses unscope(where: \"widgets.tenant_id\")" do
      refused { Widget.unscope(where: "widgets.tenant_id").to_a }
    end

    it "refuses unscope(:where)" do
      refused { Widget.unscope(:where).to_a }
    end

    it "refuses an or with another tenant's association" do
      refused { Widget.where(name: "B-1").or(tenant_a.widgets).to_a }
    end

    it "refuses where(tenant_id: other)" do
      refused { Widget.where(tenant_id: tenant_a.id).to_a }
    end

    it "refuses where(tenant_id: [current, other]) as a multi-tenant read" do
      refused { Widget.where(tenant_id: [tenant_a.id, tenant_b.id]).to_a }
    end

    it "refuses unscoped.where(tenant_id: other)" do
      refused { Widget.unscoped.where(tenant_id: tenant_a.id).to_a }
    end

    it "refuses a preload of another tenant's owners" do
      refused { Tenant.where(id: [tenant_a.id, tenant_b.id]).includes(:widgets).to_a }
    end
  end

  describe "the message" do
    it "names the model and both tenant ids, never a record payload" do
      expect { TenancyDable.with_tenant(tenant_b) { tenant_a.widgets.to_a } }
        .to raise_error(TenancyDable::CrossTenantReadError) { |error|
          expect(error.message).to include("Widget", "pinned to tenant #{tenant_a.id}", "##{tenant_b.id}")
          expect(error.message).not_to include("A-1")
        }
    end

    it "says the filter was removed for an unscope" do
      expect { TenancyDable.with_tenant(tenant_b) { Widget.unscope(where: :tenant_id).to_a } }
        .to raise_error(TenancyDable::CrossTenantReadError, /with the tenant filter removed/)
    end
  end

  describe "a bulk destroy through another tenant's association" do
    it "refuses a.widgets.destroy_all and leaves A's rows intact" do
      expect { TenancyDable.with_tenant(tenant_b) { tenant_a.widgets.destroy_all } }
        .to raise_error(TenancyDable::CrossTenantReadError)

      expect(Widget.unscoped.where(tenant_id: tenant_a.id).count).to eq(2)
    end
  end

  describe "what passes" do
    it "allows rewhere(tenant_id: current)" do
      TenancyDable.with_tenant(tenant_b) do
        mine = create(:widget, tenant: tenant_b)
        expect(Widget.rewhere(tenant_id: tenant_b.id).to_a).to eq([mine])
      end
    end

    it "allows unscope(where: :tenant_id).where(tenant_id: current)" do
      TenancyDable.with_tenant(tenant_b) do
        mine = create(:widget, tenant: tenant_b)
        expect(Widget.unscope(where: :tenant_id).where(tenant_id: tenant_b.id).to_a).to eq([mine])
      end
    end

    it "allows unscope(where: :name), only the tenant fk counts" do
      TenancyDable.with_tenant(tenant_a) do
        expect(Widget.where(name: "A-1").unscope(where: :name).to_a)
          .to contain_exactly(widget_a, widget_a2)
      end
    end

    it "allows unscoped.where(id:).pick(:tenant_id), the gem's own lookup" do
      TenancyDable.with_tenant(tenant_b) do
        expect(Widget.unscoped.where(id: widget_a.id).pick(:tenant_id)).to eq(tenant_a.id)
      end
    end

    it "allows the current tenant's own association and its ids" do
      TenancyDable.with_tenant(tenant_a) do
        expect(tenant_a.widgets.to_a).to contain_exactly(widget_a, widget_a2)
        expect(tenant_a.widget_ids).to contain_exactly(widget_a.id, widget_a2.id)
        expect(tenant_a.widgets.count).to eq(2)
      end
    end

    it "allows a preload of the current tenant's owners" do
      TenancyDable.with_tenant(tenant_a) do
        loaded = Tenant.where(id: tenant_a.id).includes(:widgets).to_a
        expect(loaded.first.widgets).to contain_exactly(widget_a, widget_a2)
      end
    end

    it "allows an association pinned on another column (widget.children)" do
      child = create(:widget, tenant: tenant_a, parent: widget_a)

      TenancyDable.with_tenant(tenant_a) do
        expect(widget_a.children.to_a).to eq([child])
      end
    end

    it "allows reload" do
      TenancyDable.with_tenant(tenant_b) do
        expect { widget_a.reload }.not_to raise_error
      end
    end

    it "allows Model.count and the default scope's own reads" do
      TenancyDable.with_tenant(tenant_a) do
        expect(Widget.count).to eq(2)
        expect(Widget.all.to_a).to contain_exactly(widget_a, widget_a2)
      end
    end

    it "allows an eager_load from the tenant side" do
      TenancyDable.with_tenant(tenant_b) do
        expect(Tenant.where(id: tenant_b.id).eager_load(:widgets).to_a).to eq([tenant_b])
      end
    end

    it "allows a deliberate cross-tenant read inside without_tenant" do
      TenancyDable.with_tenant(tenant_b) do
        TenancyDable.without_tenant do
          expect(tenant_a.widgets.to_a).to contain_exactly(widget_a, widget_a2)
          expect(Widget.unscope(where: :tenant_id).count).to eq(2)
        end
      end
    end

    it "allows the same read under with_tenant(owner)" do
      TenancyDable.with_tenant(tenant_a) do
        expect(tenant_a.widgets.to_a).to contain_exactly(widget_a, widget_a2)
      end
    end

    it "leaves the decision to the default scope with no current tenant" do
      TenancyDable.configure { |c| c.require_tenant = true }

      expect { Widget.all.to_a }.to raise_error(TenancyDable::NoTenantError)
    end
  end

  it "leaves a model that is not tenant-scoped untouched" do
    TenancyDable.with_tenant(tenant_b) do
      expect(Tenant.unscope(:where).to_a).to include(tenant_a, tenant_b)
      expect(Tenant.where(id: tenant_a.id).pluck(:id)).to eq([tenant_a.id])
    end
  end

  describe "config.guard_reads = false" do
    before { TenancyDable.configure { |c| c.guard_reads = false } }

    it "restores the 0.4.0 answers for the association leak" do
      TenancyDable.with_tenant(tenant_b) do
        expect(tenant_a.widgets.to_a).to contain_exactly(widget_a, widget_a2)
        expect(tenant_a.widgets.count).to eq(2)
      end
    end

    it "restores the 0.4.0 answer for an explicit other-tenant where (empty)" do
      TenancyDable.with_tenant(tenant_b) do
        expect(Widget.where(tenant_id: tenant_a.id).to_a).to be_empty
      end
    end

    it "does not affect the bulk-write guard" do
      TenancyDable.with_tenant(tenant_b) do
        expect { Widget.where(tenant_id: tenant_a.id).delete_all }
          .to raise_error(TenancyDable::BulkWriteError)
      end
    end
  end
end
