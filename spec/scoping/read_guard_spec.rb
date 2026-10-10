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

  describe "non-equality predicates on the tenant filter (acting in B)" do
    it("refuses invert_where on a host scope") { refused { Widget.where(name: "B-1").invert_where.to_a } }
    it("refuses Widget.invert_where") { refused { Widget.invert_where.to_a } }
    it("refuses a count through invert_where") { refused { Widget.where(name: "B-1").invert_where.count } }
    it("refuses unscoped.where.not(tenant_id: other)") { refused { Widget.unscoped.where.not(tenant_id: tenant_a.id).to_a } }

    it "refuses a merge that brings a range on the fk" do
      refused { Widget.all.merge(Widget.unscoped.where(tenant_id: ..tenant_a.id)).to_a }
    end

    it "refuses a merge that brings a where.not on the fk" do
      refused { Widget.all.merge(Widget.unscoped.where.not(tenant_id: tenant_b.id)).to_a }
    end

    it "refuses unscoped.where(tenant_id: <subquery>)" do
      refused { Widget.unscoped.where(tenant_id: Tenant.where(slug: tenant_a.slug).select(:id)).to_a }
    end

    it "keeps an explicit nil pin unpinned (not refused)" do
      TenancyDable.with_tenant(tenant_b) do
        expect(Widget.unscoped.where(tenant_id: nil).to_a).to eq([])
      end
    end
  end

  describe "table-keyed Hash unscope targets (acting in B)" do
    it("refuses a Symbol-keyed table form") { refused { Widget.unscope(where: {widgets: :tenant_id}).to_a } }
    it("refuses a String-keyed table form") { refused { Widget.unscope(where: {"widgets" => ["tenant_id"]}).to_a } }
    it("refuses a list that holds a table-keyed Hash") { refused { Widget.unscope(where: [:name, {widgets: :tenant_id}]).to_a } }

    it "allows a table-keyed Hash on another column" do
      TenancyDable.with_tenant(tenant_b) do
        expect { Widget.unscope(where: {widgets: :name}).to_a }.not_to raise_error
      end
    end
  end

  describe "a relation built with no tenant filter, loaded inside a tenant (acting in B)" do
    it("refuses a relation built before any tenant was entered") do
      relation = Widget.order(:id)
      refused { relation.to_a }
    end

    it("refuses a count of such a relation") do
      relation = Widget.where.not(name: nil)
      refused { relation.count }
    end

    it("refuses pluck, ids and exists? of such a relation") do
      relation = Widget.order(:id)
      refused { relation.pluck(:name) }
      refused { relation.ids }
      refused { relation.exists? }
    end

    it("refuses a relation built inside without_tenant") do
      relation = TenancyDable.without_tenant { Widget.order(:id) }
      refused { relation.to_a }
    end

    it "allows a marked relation merged into one pinned to the current tenant" do
      marked = Widget.order(:id)
      TenancyDable.with_tenant(tenant_b) { expect(Widget.all.merge(marked).to_a).to eq([]) }
    end

    it "allows a relation built outside that is pinned to the current tenant" do
      relation = Widget.where(tenant_id: tenant_b.id)
      TenancyDable.with_tenant(tenant_b) { expect(relation.to_a).to eq([]) }
    end

    it "allows the same relation loaded with no tenant current" do
      expect(Widget.order(:id).to_a).to eq([widget_a, widget_a2])
    end

    it "allows the same relation loaded inside without_tenant" do
      relation = Widget.order(:id)
      TenancyDable.with_tenant(tenant_b) do
        TenancyDable.without_tenant { expect(relation.to_a).to eq([widget_a, widget_a2]) }
      end
    end

    it "allows a relation built inside the current tenant" do
      mine = TenancyDable.with_tenant(tenant_b) { create(:widget, tenant: tenant_b) }
      TenancyDable.with_tenant(tenant_b) do
        relation = Widget.order(:id)
        expect(relation.to_a).to eq([mine])
      end
    end

    it "does not mark Model.unscoped (documented residual)" do
      expect(Widget.unscoped).not_to be_a(TenancyDable::BuiltWithoutTenant)
    end
  end

  describe "collection cache keys (acting in B)" do
    it("refuses cache_key of another tenant's association") { refused { tenant_a.widgets.cache_key } }
    it("refuses cache_key when the tenant filter was removed") { refused { Widget.unscope(where: :tenant_id).cache_key } }

    it "refuses cache_version and cache_key_with_version with collection cache versioning on" do
      previous = Widget.collection_cache_versioning
      Widget.collection_cache_versioning = true
      refused { tenant_a.widgets.cache_version }
      refused { Widget.unscope(where: :tenant_id).cache_key_with_version }
    ensure
      Widget.collection_cache_versioning = previous
    end

    it "allows the current tenant's own cache key" do
      TenancyDable.with_tenant(tenant_a) { expect(tenant_a.widgets.cache_key).to start_with("widgets/") }
    end
  end

  describe "a scoped relation compiled into another model's query (acting in B)" do
    it "refuses a where-subquery over another tenant's rows" do
      refused { Tenant.where(id: Widget.unscope(where: :tenant_id).select(:tenant_id)).pluck(:slug) }
    end

    it("refuses a from-subquery") { refused { Tenant.from(tenant_a.widgets.select(:id, :name), :tenants).to_a } }

    it "refuses a CTE" do
      refused { Tenant.with(w: tenant_a.widgets.select(:id)).from("w").to_a }
    end

    it "refuses to_sql of a refused relation" do
      refused { tenant_a.widgets.to_sql }
    end

    it "allows a subquery over the current tenant's rows" do
      TenancyDable.with_tenant(tenant_a) do
        expect(Tenant.where(id: Widget.select(:tenant_id)).pluck(:id)).to eq([tenant_a.id])
      end
    end
  end

  describe "load_async with an async executor (acting in B)" do
    before do
      allow_any_instance_of(ActiveRecord::ConnectionAdapters::SQLite3Adapter)
        .to receive(:async_enabled?).and_return(true)
    end

    it("refuses load_async before the query is scheduled") { refused { tenant_a.widgets.load_async } }
    it("refuses async_count") { refused { tenant_a.widgets.async_count.value } }
    it("refuses async_pluck") { refused { tenant_a.widgets.async_pluck(:name).value } }
    it("refuses async_ids") { refused { tenant_a.widgets.async_ids.value } }
    it("refuses async_sum") { refused { tenant_a.widgets.async_sum(:id).value } }
  end

  describe "a preload from a single owner (acting in B)" do
    it("refuses Tenant.where(id: a).includes(:widgets)") do
      refused { Tenant.where(id: tenant_a.id).includes(:widgets).to_a }
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

    it "passes a fail-open read with no current tenant and require_tenant off (rule 3)" do
      expect(Widget.order(:id).to_a).to eq([widget_a, widget_a2])
      expect(Widget.count).to eq(2)
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

  describe "the classifier reads literal pins from the where clause" do
    let(:arel) { Widget.arel_table }

    def reads(&block) = TenancyDable.with_tenant(tenant_b, &block)

    before { create(:widget, tenant: tenant_b, name: "B-1") }

    it "reads a scoped model with a case-insensitive uniqueness validation inside its tenant" do
      model = Class.new(ApplicationRecord) do
        self.table_name = "gadgets"
        include TenancyDable::Scoped

        belongs_to_tenant
        validates :name, uniqueness: {scope: :tenant_id, case_sensitive: false}

        def self.name = "CiGadget"
      end
      stub_const("CiGadget", model)

      reads do
        expect(CiGadget.create(name: "Alpha")).to be_persisted
        expect(CiGadget.new(name: "ALPHA")).not_to be_valid
      end
    end

    it "validates_uniqueness_to_tenant with case_sensitive: false saves inside its tenant" do
      model = Class.new(ApplicationRecord) do
        self.table_name = "gadgets"
        include TenancyDable::Scoped

        belongs_to_tenant
        validates_uniqueness_to_tenant :name, case_sensitive: false

        def self.name = "CiToTenantGadget"
      end
      stub_const("CiToTenantGadget", model)

      reads { expect(CiToTenantGadget.create(name: "Beta")).to be_persisted }
    end

    it "reads where(arel_table[:name].lower.eq(...)) inside a tenant" do
      reads do
        Gadget.create!(name: "Gamma")
        expect(Gadget.where(Gadget.arel_table[:name].lower.eq("gamma")).count).to eq(1)
      end
    end

    it "refuses an Arel equality on the fk against a subquery, through merge and unscoped" do
      subquery = Tenant.where(id: tenant_a.id).select(:id).arel

      refused { Widget.all.merge(Widget.unscoped.where(arel[:tenant_id].eq(subquery))).to_a }
      refused { Widget.unscoped.where(arel[:tenant_id].eq(subquery)).to_a }
    end

    it "refuses an Arel equality on the fk against a column or an Arel.sql literal" do
      refused { Widget.all.merge(Widget.unscoped.where(arel[:tenant_id].eq(arel[:tenant_id]))).to_a }
      refused { Widget.all.merge(Widget.unscoped.where(arel[:tenant_id].eq(Arel.sql(tenant_a.id.to_s)))).to_a }
    end

    it "still reads Tenant.where(id: b).eager_load(:widgets)" do
      reads do
        tenants = Tenant.where(id: tenant_b.id).eager_load(:widgets).to_a
        expect(tenants.flat_map { |tenant| tenant.widgets.map(&:name) }).to eq(["B-1"])
      end
    end

    it "reads a where(tenant: <subquery of the current tenant>) ANDed with the default scope" do
      reads { expect(Widget.where(tenant: Tenant.where(id: tenant_b.id)).map(&:name)).to eq(["B-1"]) }
    end

    it "reads where(tenant_id: [b, b]) and where(tenant_id: [])" do
      reads do
        expect(Widget.where(tenant_id: [tenant_b.id, tenant_b.id]).count).to eq(1)
        expect(Widget.where(tenant_id: []).count).to eq(0)
      end
    end

    it "names the other tenant of a list pin in the message" do
      expect { reads { Widget.unscoped.where(tenant_id: [tenant_b.id, tenant_a.id]).to_a } }
        .to raise_error(TenancyDable::CrossTenantReadError, /pinned to tenant \[#{tenant_b.id}, #{tenant_a.id}\]/)
    end

    it "refuses stale.dup, which drops the singleton marker" do
      stale = TenancyDable::Current.set(tenant: nil) { Widget.where.not(name: nil) }

      refused { stale.dup.to_a }
    end
  end
end
