# frozen_string_literal: true

require "rails_helper"

# Tenant foreign-key lifecycle on a scoped model (DESIGN.md §5.1):
#   * create-time auto-assignment from current_tenant when the fk is blank,
#   * immutability of the fk after the record is persisted (invariant 3).
RSpec.describe "TenancyDable::Scoped — tenant_id assignment" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  describe "auto-assignment on create" do
    it "assigns tenant_id from the current tenant when left blank" do
      widget = TenancyDable.with_tenant(tenant_a) { Widget.create!(name: "Auto") }

      expect(widget.tenant_id).to eq(tenant_a.id)
    end

    it "does not override an explicitly provided tenant_id" do
      widget = TenancyDable.with_tenant(tenant_a) { create(:widget, tenant: tenant_b) }

      expect(widget.tenant_id).to eq(tenant_b.id)
    end

    it "leaves tenant_id blank when there is no current tenant (fail-open create)" do
      widget = Widget.new(name: "Orphan")

      expect(widget.tenant_id).to be_nil
    end
  end

  describe "immutability after persist (invariant 3)" do
    it "raises TenantImmutableError when the fk writer reassigns a persisted record" do
      widget = create(:widget, tenant: tenant_a)

      expect { widget.tenant_id = tenant_b.id }
        .to raise_error(TenancyDable::TenantImmutableError)
    end

    it "raises TenantImmutableError when the tenant association is reassigned on save" do
      # `record.tenant = other` writes the fk via write_attribute, slipping past
      # the fk-writer override; the before_update backstop is what catches it.
      widget = create(:widget, tenant: tenant_a)
      widget.tenant = tenant_b

      expect { widget.save! }.to raise_error(TenancyDable::TenantImmutableError)
    end

    it "allows reassigning the SAME tenant_id to a persisted record (no-op)" do
      widget = create(:widget, tenant: tenant_a)

      expect { widget.tenant_id = tenant_a.id }.not_to raise_error
    end

    it "allows setting tenant_id on a new, unpersisted record" do
      widget = build(:widget, tenant: tenant_a)

      expect { widget.tenant_id = tenant_b.id }.not_to raise_error
      expect(widget.tenant_id).to eq(tenant_b.id)
    end
  end
end
