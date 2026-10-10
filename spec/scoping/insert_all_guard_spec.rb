# frozen_string_literal: true

require "rails_helper"

# insert_all / upsert_all skip callbacks, so the guard sits on InsertAll itself
# (DESIGN.md §16.2): every row must land in the current tenant, and an upsert
# must resolve a conflict target that includes the tenant fk.
RSpec.describe "TenancyDable::InsertAllExtension" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  def acting_in_b(&block) = TenancyDable.with_tenant(tenant_b, &block)

  def names(tenant) = TenancyDable.without_tenant { Widget.where(tenant_id: tenant.id).order(:name).pluck(:name) }

  def row(id) = TenancyDable.without_tenant { Widget.find(id).attributes.slice("name", "tenant_id") }

  describe "the fk rule" do
    before { tenant_a && tenant_b }

    it "refuses tenant_a.widgets.insert_all" do
      expect { acting_in_b { tenant_a.widgets.insert_all([{name: "p"}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError, /tenant ##{tenant_a.id} while acting in tenant ##{tenant_b.id}/)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses tenant_a.widgets.insert" do
      expect { acting_in_b { tenant_a.widgets.insert({name: "p"}) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses tenant_a.widgets.insert_all!" do
      expect { acting_in_b { tenant_a.widgets.insert_all!([{name: "p"}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses tenant_a.widgets.upsert_all" do
      expect { acting_in_b { tenant_a.widgets.upsert_all([{name: "p"}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses Widget.where(tenant_id: a).insert_all" do
      expect { acting_in_b { Widget.where(tenant_id: tenant_a.id).insert_all([{name: "p"}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses a row that names another tenant when the relation adds none" do
      expect { acting_in_b { Widget.unscoped.insert_all([{name: "p", tenant_id: tenant_a.id}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_a)).to eq([])
    end

    it "refuses a row with no tenant at all" do
      expect { acting_in_b { Widget.unscoped.insert_all([{name: "p"}]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError, /into no tenant/)
    end

    it "refuses the whole batch when one row is foreign, writing none" do
      expect {
        acting_in_b do
          Widget.unscoped.insert_all([{name: "ok", tenant_id: tenant_b.id}, {name: "bad", tenant_id: tenant_a.id}])
        end
      }.to raise_error(TenancyDable::CrossTenantWriteError)
      expect(names(tenant_b)).to eq([])
    end
  end

  describe "the upsert rule" do
    let!(:widget_a) { create(:widget, tenant: tenant_a, name: "A-1") }

    before { tenant_b }

    it "refuses Widget.upsert on the primary key" do
      expect { acting_in_b { Widget.upsert({id: widget_a.id, name: "stolen"}) } }
        .to raise_error(TenancyDable::CrossTenantWriteError, /conflict target/)
      expect(row(widget_a.id)).to eq("name" => "A-1", "tenant_id" => tenant_a.id)
    end

    it "refuses tenant_a.widgets.upsert on the primary key" do
      expect { acting_in_b { tenant_a.widgets.upsert({id: widget_a.id, name: "overwritten"}) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(row(widget_a.id)).to eq("name" => "A-1", "tenant_id" => tenant_a.id)
    end

    it "refuses upsert_all with update_only on the primary key, in the current tenant" do
      mine = create(:widget, tenant: tenant_b, name: "B-1")

      expect { acting_in_b { Widget.upsert_all([{id: mine.id, name: "renamed"}], update_only: [:name]) } }
        .to raise_error(TenancyDable::CrossTenantWriteError)
      expect(row(mine.id)).to include("name" => "B-1")
    end

    it "refuses an upsert whose resolved unique_by lacks the fk" do
      stub_unique_by(%w[name])

      expect { acting_in_b { Widget.upsert({name: "x"}) } }.to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "refuses every upsert when the adapter resolves no conflict target" do
      stub_unique_by(nil)

      expect { acting_in_b { Widget.upsert({name: "x"}) } }.to raise_error(TenancyDable::CrossTenantWriteError)
    end

    it "allows an upsert whose resolved unique_by includes the fk" do
      # The harness has no unique index spanning the fk, so the resolution is
      # stubbed and the SQL is not run: only the guard is under test.
      stub_unique_by(%w[tenant_id name])
      allow_any_instance_of(ActiveRecord::InsertAll).to receive(:execute)

      expect { acting_in_b { Widget.upsert({name: "x"}) } }.not_to raise_error
    end

    it "does not apply the upsert rule to insert_all (skip) or insert_all! (raise)" do
      acting_in_b do
        Widget.insert_all([{name: "skip"}])
        Widget.insert_all!([{name: "raise"}])
      end

      expect(names(tenant_b)).to eq(%w[raise skip])
    end

    # Replaces the index resolution with one whose columns are `columns` (nil: no index).
    def stub_unique_by(columns)
      index = columns && ActiveRecord::ConnectionAdapters::IndexDefinition.new("widgets", "stubbed", true, columns)
      allow_any_instance_of(ActiveRecord::InsertAll).to receive(:find_unique_index_for).and_return(index)
    end
  end

  describe "what passes through" do
    it "inserts from the class in the current tenant" do
      acting_in_b do
        Widget.insert_all([{name: "one"}, {name: "two"}])
        tenant_b.widgets.insert({name: "three"})
        Widget.where(tenant_id: tenant_b.id).insert_all!([{name: "four"}])
      end

      expect(names(tenant_b)).to eq(%w[four one three two])
    end

    it "accepts a row that names the current tenant" do
      acting_in_b { Widget.insert_all([{name: "own", tenant_id: tenant_b.id}]) }

      expect(names(tenant_b)).to eq(["own"])
    end

    it "does not guard with no current tenant" do
      Widget.insert_all([{name: "a", tenant_id: tenant_a.id}])
      Widget.upsert({name: "b", tenant_id: tenant_a.id})

      expect(names(tenant_a)).to eq(%w[a b])
    end

    it "does not guard inside without_tenant" do
      acting_in_b do
        TenancyDable.without_tenant do
          Widget.insert_all([{name: "a", tenant_id: tenant_a.id}])
          Widget.upsert({name: "b", tenant_id: tenant_a.id})
        end
      end

      expect(names(tenant_a)).to eq(%w[a b])
    end

    it "does not guard a model that is not tenant-scoped" do
      acting_in_b do
        Tenant.insert_all([{slug: "one", created_at: Time.current, updated_at: Time.current}])
        Tenant.upsert({slug: "one", name: "renamed", created_at: Time.current, updated_at: Time.current}, unique_by: :slug)
      end

      expect(Tenant.find_by(slug: "one").name).to eq("renamed")
    end
  end

  describe "empty inserts and composite primary keys" do
    it "no-ops insert_all([]) and upsert_all([]) inside a tenant" do
      expect { acting_in_b { Widget.insert_all([]) } }.not_to raise_error
      expect { acting_in_b { Widget.upsert_all([]) } }.not_to raise_error
    end

    it "accepts upsert_all with no unique_by when the primary key spans the fk" do
      ActiveRecord::Base.connection.create_table(:cpk_items, primary_key: [:tenant_id, :id], force: true) do |t|
        t.integer :tenant_id, null: false
        t.integer :id, null: false
        t.string :name
      end
      stub_const("CpkItem", Class.new(ApplicationRecord) do
        self.table_name = "cpk_items"
        include TenancyDable::Scoped

        belongs_to_tenant

        def self.name = "CpkItem"
      end)

      acting_in_b do
        expect { CpkItem.upsert_all([{id: 1, name: "x"}]) }.not_to raise_error
        expect(CpkItem.pluck(:name)).to eq(["x"])
      end
    ensure
      ActiveRecord::Base.connection.drop_table(:cpk_items, if_exists: true)
    end
  end
end
