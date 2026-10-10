# frozen_string_literal: true

require "rails_helper"

# Declared tenancy (DESIGN.md §16.3): `tenant_global`, the readers, the frozen
# `tenancy_declare!` rule, and the identity concerns' own declarations.
RSpec.describe TenancyDable::Declarations do
  # A fresh, named throwaway model on an existing table; `stub_const` removes
  # the constant after the example so nothing leaks into other specs.
  def stub_model(const, table: "unindexed_records", parent: ApplicationRecord, &body)
    klass = Class.new(parent) { self.table_name = table }
    stub_const(const, klass)
    klass.class_eval(&body) if body
    klass
  end

  describe ".tenant_global" do
    it "stores a frozen Declaration and returns it" do
      model = stub_model("GlobalThing")
      declaration = model.tenant_global because: "shared reference data", tag: :reference

      expect(declaration).to be_a(TenancyDable::Declaration)
      expect(declaration).to have_attributes(kind: :global, reason: "shared reference data", tag: :reference, allow_tenant_fk: false)
      expect(declaration).to be_frozen
      expect(declaration.reason).to be_frozen
      expect(model.tenancy_declaration).to eq(declaration)
    end

    it "does not alias the caller's reason string" do
      reason = +"mutable reason"
      model = stub_model("GlobalThing")
      model.tenant_global because: reason
      reason << " changed"

      expect(model.tenancy_global_reason).to eq("mutable reason")
    end

    it "refuses a blank reason with ConfigurationError, storing nothing" do
      model = stub_model("GlobalThing")

      [nil, "", "   ", :symbol, 3].each do |bad|
        expect { model.tenant_global because: bad }
          .to raise_error(TenancyDable::ConfigurationError, "GlobalThing: tenant_global requires a non-blank because: reason")
      end
      expect(model.tenancy_declaration).to be_nil
    end

    it "validates the tag" do
      model = stub_model("GlobalThing")

      expect { model.tenant_global because: "x", tag: 1 }
        .to raise_error(TenancyDable::ConfigurationError, "GlobalThing: tag must be a Symbol or String")
      expect(model.tenancy_declaration).to be_nil
      expect(model.tenant_global(because: "x", tag: "billing").tag).to eq("billing")
    end

    it "validates allow_tenant_fk" do
      model = stub_model("GlobalThing")

      expect { model.tenant_global because: "x", allow_tenant_fk: "yes" }
        .to raise_error(TenancyDable::ConfigurationError, "GlobalThing: allow_tenant_fk must be true or false")
      expect(model.tenant_global(because: "x", allow_tenant_fk: true).allow_tenant_fk).to be(true)
    end

    it "names an anonymous model in its errors" do
      model = Class.new(ApplicationRecord) { self.table_name = "unindexed_records" }

      expect { model.tenant_global because: "" }
        .to raise_error(TenancyDable::ConfigurationError, /\Aan anonymous model: tenant_global requires/)
    end

    it "checks the reason before the tag and the tag before the flag" do
      model = stub_model("GlobalThing")

      expect { model.tenant_global because: "", tag: 1, allow_tenant_fk: 1 }
        .to raise_error(TenancyDable::ConfigurationError, /because: reason/)
      expect { model.tenant_global because: "x", tag: 1, allow_tenant_fk: 1 }
        .to raise_error(TenancyDable::ConfigurationError, /tag must be/)
    end
  end

  describe "the readers" do
    it "answer nil on an undeclared model and on ActiveRecord::Base" do
      model = stub_model("Undeclared")

      expect(model.tenancy_declaration).to be_nil
      expect(model.tenancy_global_reason).to be_nil
      expect(model.tenancy_tag).to be_nil
      expect(ActiveRecord::Base.tenancy_declaration).to be_nil
    end

    it "expose the reason and the tag of a global model" do
      model = stub_model("GlobalThing")
      model.tenant_global because: "shared", tag: "ops"

      expect(model.tenancy_global_reason).to eq("shared")
      expect(model.tenancy_tag).to eq("ops")
    end

    it "expose a scoped model's tag, with no reason and no fk allowance" do
      model = stub_model("ScopedThing", table: "widgets") do
        include TenancyDable::Scoped

        belongs_to_tenant tag: :core
      end

      expect(model.tenancy_declaration).to have_attributes(kind: :scoped, reason: nil, tag: :core, allow_tenant_fk: false)
      expect(model.tenancy_global_reason).to be_nil
      expect(model.tenancy_tag).to eq(:core)
    end

    it "report tenant_scoped? only on scoped classes" do
      global = stub_model("GlobalThing")
      global.tenant_global because: "x"

      expect(global).not_to respond_to(:tenant_scoped?)
      expect(Widget).to respond_to(:tenant_scoped?)
    end
  end

  describe "belongs_to_tenant" do
    it "does not forward tag: to belongs_to" do
      expect {
        stub_model("ScopedThing", table: "widgets") do
          include TenancyDable::Scoped

          belongs_to_tenant :tenant, tag: :core
        end
      }.not_to raise_error
    end

    it "raises on a second belongs_to_tenant before installing anything" do
      model = stub_model("ScopedThing", table: "widgets") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      callbacks = model._validate_callbacks.count

      expect { model.belongs_to_tenant }
        .to raise_error(TenancyDable::ConfigurationError, "ScopedThing already declared its tenancy (scoped); a declaration cannot be changed")
      expect(model._validate_callbacks.count).to eq(callbacks)
    end

    it "refuses a bad tag before belongs_to runs" do
      model = stub_model("ScopedThing", table: "widgets") { include TenancyDable::Scoped }

      expect { model.belongs_to_tenant tag: 1 }.to raise_error(TenancyDable::ConfigurationError, /tag must be/)
      expect(model.reflect_on_association(:tenant)).to be_nil
    end
  end

  describe "no re-declaration" do
    it "refuses belongs_to_tenant after tenant_global" do
      model = stub_model("GlobalThing") { include TenancyDable::Scoped }
      model.tenant_global because: "x"

      expect { model.belongs_to_tenant }
        .to raise_error(TenancyDable::ConfigurationError, /already declared its tenancy \(global\)/)
    end

    it "refuses tenant_global after belongs_to_tenant" do
      model = stub_model("ScopedThing", table: "widgets") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end

      expect { model.tenant_global because: "x" }
        .to raise_error(TenancyDable::ConfigurationError, /already declared its tenancy \(scoped\)/)
    end

    it "refuses any declaration on a subclass of a declared class (STI), weaker included" do
      parent = stub_model("ScopedParent", table: "widgets") do
        include TenancyDable::Scoped

        belongs_to_tenant
      end
      child = Class.new(parent)
      stub_const("ScopedChild", child)

      expect(child.tenancy_declaration).to equal(parent.tenancy_declaration)
      expect { child.tenant_global because: "weaker" }
        .to raise_error(TenancyDable::ConfigurationError, "ScopedChild already declared its tenancy (scoped); a declaration cannot be changed")
    end

    it "refuses tenant_global on a base class below which models declare themselves" do
      base = stub_model("BlanketBase", parent: ActiveRecord::Base) { self.abstract_class = true }
      base.tenant_global because: "blanket"
      child = Class.new(base) { self.table_name = "unindexed_records" }
      stub_const("BlanketChild", child)

      expect(child.tenancy_declaration.kind).to eq(:global)
      expect { child.tenant_global because: "again" }.to raise_error(TenancyDable::ConfigurationError)
    end

    it "keeps a declaration on one class from reaching a sibling" do
      one = stub_model("OneThing")
      two = stub_model("TwoThing")
      one.tenant_global because: "x"

      expect(two.tenancy_declaration).to be_nil
    end
  end

  describe "the identity concerns" do
    it "declare Tenant global because it is the boundary" do
      expect(Tenant.tenancy_declaration).to have_attributes(
        kind: :global, reason: "the tenant model is the tenancy boundary itself", allow_tenant_fk: false
      )
    end

    it "declare User global because it spans tenants" do
      expect(User.tenancy_declaration).to have_attributes(
        kind: :global, reason: "a user spans tenants through memberships", allow_tenant_fk: false
      )
    end

    it "declare Membership global and allowed to carry the tenant fk" do
      expect(Membership.tenancy_declaration).to have_attributes(
        kind: :global, reason: "memberships are read before any tenant is current (DESIGN.md §5.3)", allow_tenant_fk: true
      )
    end

    it "refuse a second declaration on a host model that includes one" do
      expect { Tenant.tenant_global because: "again" }.to raise_error(TenancyDable::ConfigurationError)
    end
  end
end
