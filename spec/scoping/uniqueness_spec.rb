# frozen_string_literal: true

require "rails_helper"

# `validates_uniqueness_to_tenant :name` on Widget (DESIGN.md §5.1/§8). The
# helper merges the tenant fk into the uniqueness scope, so a name must be
# unique WITHIN a workspace but may repeat across workspaces. The fixture schema
# deliberately keeps widgets[tenant_id, name] non-unique at the DB level so the
# model validation is the system-under-test here. Examples run with no current
# tenant, so the validation's explicit fk scope is the only tenant filter.
RSpec.describe "TenancyDable::Scoped — validates_uniqueness_to_tenant" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  it "rejects a duplicate name within the same tenant" do
    create(:widget, tenant: tenant_a, name: "Gearbox")
    duplicate = build(:widget, tenant: tenant_a, name: "Gearbox")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "allows the same name in a different tenant" do
    create(:widget, tenant: tenant_a, name: "Gearbox")
    other = build(:widget, tenant: tenant_b, name: "Gearbox")

    expect(other).to be_valid
  end
end
