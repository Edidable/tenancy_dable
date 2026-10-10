# frozen_string_literal: true

require "rails_helper"

# The declaration audit (DESIGN.md §16.3). Throwaway models are named with
# `stub_const` on the harness's `widgets` / `unindexed_records` tables; once the
# constant is gone the audit sees a stale descendant and skips it.
RSpec.describe TenancyDable::Audit do
  def stub_model(const, table: "unindexed_records", parent: ApplicationRecord, &body)
    klass = Class.new(parent) { self.table_name = table }
    stub_const(const, klass)
    klass.class_eval(&body) if body
    klass
  end

  def kinds(findings) = findings.map(&:kind)

  it "is clean for the harness with no argument" do
    expect(TenancyDable.audit).to be_empty
  end

  it "returns a frozen Array" do
    expect(TenancyDable.audit).to be_frozen
    expect(TenancyDable.audit([Widget])).to be_frozen
  end

  describe ":undeclared" do
    it "flags a model that declares nothing, with the fix in the message" do
      model = stub_model("Forgotten")
      findings = TenancyDable.audit([model])

      expect(findings.size).to eq(1)
      expect(findings.first).to have_attributes(model: model, kind: :undeclared)
      expect(findings.first.message).to eq('declares no tenancy; add belongs_to_tenant, or tenant_global because: "..."')
      expect(findings.first.to_s).to eq("Forgotten: #{findings.first.message}")
    end

    it "is found through the no-argument form while the constant lives, and not after" do
      stub_model("Forgotten")
      expect(TenancyDable.audit.map(&:model).map(&:name)).to eq(["Forgotten"])
    end

    it "still checks a model whose table does not exist" do
      model = stub_model("Orphan", table: "no_such_table")

      expect(kinds(TenancyDable.audit([model]))).to eq([:undeclared])
    end
  end

  describe ":global_with_tenant_fk" do
    it "flags a global model with a tenant_id column" do
      model = stub_model("LeakyGlobal") { tenant_global because: "x" }
      findings = TenancyDable.audit([model])

      expect(kinds(findings)).to eq([:global_with_tenant_fk])
      expect(findings.first.message).to eq(
        "is declared tenant_global but has a tenant_id column; scope it with belongs_to_tenant, " \
        "or pass allow_tenant_fk: true if it is deliberately unscoped"
      )
    end

    it "accepts allow_tenant_fk: true" do
      model = stub_model("Invitation") { tenant_global because: "looked up by token", allow_tenant_fk: true }

      expect(TenancyDable.audit([model])).to be_empty
    end

    it "flags a global model on the table of a scoped model, even with allow_tenant_fk" do
      scoped = stub_model("ScopedGadget", table: "gadgets") {
        include TenancyDable::Scoped

        belongs_to_tenant
      }
      twin = stub_model("GlobalGadget", table: "gadgets") { tenant_global because: "x", allow_tenant_fk: true }
      findings = TenancyDable.audit([scoped, twin])

      expect(findings.map { |f| [f.model, f.kind] }).to eq([[twin, :global_with_tenant_fk]])
      expect(findings.first.message).to include("shares its table with a tenant-scoped model")
    end

    it "does not flag the same global model when no scoped model shares its table" do
      twin = stub_model("GlobalGadget", table: "gadgets") { tenant_global because: "x", allow_tenant_fk: true }

      expect(TenancyDable.audit([twin])).to be_empty
    end

    it "does not flag a global model with no such column" do
      model = stub_model("Plain") { tenant_global because: "x" }
      allow(model).to receive(:column_names).and_return(%w[id name])

      expect(TenancyDable.audit([model])).to be_empty
    end

    it "follows a configured tenant_fk" do
      TenancyDable.configure { |c| c.tenant_fk = :workspace_id }
      model = stub_model("Plain") { tenant_global because: "x" }

      expect(TenancyDable.audit([model])).to be_empty
    end
  end

  describe ":scoped_without_index" do
    it "flags a scoped model whose tenant_id has no index" do
      model = stub_model("Unindexed") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      findings = TenancyDable.audit([model])

      expect(kinds(findings)).to eq([:scoped_without_index])
      expect(findings.first.message).to eq("is tenant-scoped but no index leads with tenant_id")
    end

    it "counts a composite index that leads with the fk (widgets[tenant_id, name])" do
      expect(TenancyDable.audit([Widget])).to be_empty
    end

    it "counts a plain single-column index (gadgets.tenant_id)" do
      expect(TenancyDable.audit([Gadget])).to be_empty
    end

    it "does not count an index where the fk is not first" do
      model = stub_model("Unindexed") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      index = instance_double(ActiveRecord::ConnectionAdapters::IndexDefinition, columns: %w[name tenant_id])
      allow_any_instance_of(ActiveRecord::ConnectionAdapters::SQLite3Adapter).to receive(:indexes).and_return([index])

      expect(kinds(TenancyDable.audit([model]))).to eq([:scoped_without_index])
    end

    it "counts a composite primary key that leads with the fk" do
      model = stub_model("Composite") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      allow(model).to receive(:primary_key).and_return(%w[tenant_id id])

      expect(TenancyDable.audit([model])).to be_empty
    end
  end

  describe "what is skipped" do
    it "skips abstract classes" do
      base = stub_model("AbstractBase", parent: ActiveRecord::Base) { self.abstract_class = true }

      expect(TenancyDable.audit([base])).to be_empty
    end

    it "skips an STI subclass, whose base class answers for the table" do
      parent = stub_model("Parent") { tenant_global because: "x", allow_tenant_fk: true }
      child = Class.new(parent)
      stub_const("Child", child)
      allow(child).to receive(:base_class).and_return(parent)

      expect(TenancyDable.audit([child])).to be_empty
    end

    it "audits a subclass that points at another table, since it is not STI" do
      parent = stub_model("Parent") { tenant_global because: "x" }
      child = Class.new(parent) { self.table_name = "gadgets" }
      stub_const("Child", child)
      allow(child).to receive(:base_class).and_return(parent)

      expect(TenancyDable.audit([child]).map { |f| [f.model, f.kind] }).to eq([[child, :global_with_tenant_fk]])
    end

    it "skips anonymous classes in the no-argument form" do
      Class.new(ApplicationRecord) { self.table_name = "unindexed_records" }

      expect(TenancyDable.audit).to be_empty
    end

    it "skips stale descendants whose constant is gone in the no-argument form" do
      stub_const("Ghost", Class.new(ApplicationRecord) { self.table_name = "unindexed_records" })
      expect(TenancyDable.audit.map { |f| f.model.name }).to eq(["Ghost"])

      RSpec::Mocks.space.reset_all # unstubs Ghost; the class is still a descendant
      expect(TenancyDable.audit).to be_empty
    end

    it "skips the ignored namespaces, by exact name and by prefix" do
      stub_const("SolidQueue", Module.new)
      model = stub_model("SolidQueue::Job")
      exact = stub_model("ActiveStorage")

      expect(TenancyDable.audit([model, exact])).to be_empty
    end

    it "follows a configured audit_ignored_namespaces" do
      TenancyDable.configure { |c| c.audit_ignored_namespaces += [:Vendor] }
      stub_const("Vendor", Module.new)
      model = stub_model("Vendor::Thing")
      lookalike = stub_model("VendorThing")

      expect(TenancyDable.audit([model, lookalike]).map(&:model)).to eq([lookalike])
    end

    it "skips a model named in audit_allowed" do
      TenancyDable.configure { |c| c.audit_allowed = {"LibraryRecord" => "owned by a library, reviewed"} }
      model = stub_model("LibraryRecord")

      expect(TenancyDable.audit([model])).to be_empty
    end
  end

  describe "explicit models" do
    it "are not eager-loaded and not name-filtered" do
      expect(::Rails.application).not_to receive(:eager_load!)
      anonymous = Class.new(ApplicationRecord) { self.table_name = "unindexed_records" }
      allow(anonymous).to receive(:name).and_return("Anon")

      expect(kinds(TenancyDable.audit(anonymous))).to eq([:undeclared])
    end

    it "accept a single class or an Array" do
      model = stub_model("Forgotten")

      expect(TenancyDable.audit(model).size).to eq(1)
      expect(TenancyDable.audit([model]).size).to eq(1)
    end

    it "eager-loads the application when called with no argument" do
      expect(::Rails.application).to receive(:eager_load!)

      TenancyDable.audit
    end
  end

  describe "ordering" do
    it "sorts by model name, then by kind order" do
      zed = stub_model("Zed") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      alpha = stub_model("Alpha") { tenant_global because: "x" }
      mid = stub_model("Mid")

      findings = TenancyDable.audit([zed, mid, alpha])

      expect(findings.map { |f| [f.model.name, f.kind] }).to eq(
        [["Alpha", :global_with_tenant_fk], ["Mid", :undeclared], ["Zed", :scoped_without_index]]
      )
    end
  end
end
