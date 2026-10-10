# frozen_string_literal: true

require "rails_helper"

# Trivial sanity check that the Combustion harness boots and the DESIGN.md §8
# fixture schema is present and usable. Later phases add the real behavioural
# specs under spec/scoping, spec/identity, spec/resolution, spec/policy, etc.;
# this one only proves the harness itself works.
RSpec.describe "Combustion fixture schema" do
  let(:connection) { ActiveRecord::Base.connection }

  it "boots Combustion with the six fixture tables" do
    expect(connection.tables).to include(
      "tenants", "users", "memberships", "widgets", "gadgets", "unindexed_records"
    )
  end

  it "indexes gadgets.tenant_id and leaves unindexed_records.tenant_id without an index" do
    expect(connection.indexes("gadgets").map(&:columns)).to include(["tenant_id"])
    expect(connection.indexes("unindexed_records")).to be_empty
    expect(connection.columns("unindexed_records").map(&:name)).to include("tenant_id")
  end

  it "enforces the slug NOT NULL + unique contract on tenants" do
    expect(Tenant.columns_hash["slug"].null).to be(false)

    slug_index = connection.indexes("tenants").find { |i| i.columns == ["slug"] }
    expect(slug_index).not_to be_nil
    expect(slug_index.unique).to be(true)
  end

  it "scopes membership uniqueness by [user_id, tenant_id]" do
    index = connection.indexes("memberships")
      .find { |i| i.columns.sort == ["tenant_id", "user_id"] }
    expect(index).not_to be_nil
    expect(index.unique).to be(true)
  end

  it "keeps widgets[tenant_id, name] non-unique so the model validation is the SUT" do
    index = connection.indexes("widgets").find { |i| i.columns == ["tenant_id", "name"] }
    expect(index).not_to be_nil
    expect(index.unique).to be(false)
  end

  it "gives widgets a nullable self-referential parent_id" do
    expect(Widget.columns_hash["parent_id"].null).to be(true)
  end

  it "round-trips records through the factories" do
    tenant = create(:tenant)
    user = create(:user)
    membership = create(:membership, user: user, tenant: tenant)
    widget = create(:widget, tenant: tenant)

    expect(tenant).to be_persisted
    expect(tenant.slug).to be_present
    expect(user.email).to be_present
    expect(membership.user_id).to eq(user.id)
    expect(membership.tenant_id).to eq(tenant.id)
    expect(membership.role).to eq("member")
    expect(widget.tenant_id).to eq(tenant.id)
    expect(widget.parent_id).to be_nil

    gadget = create(:gadget, tenant: tenant)
    expect(gadget.tenant_id).to eq(tenant.id)
  end

  it "reads widgets and gadgets through the tenant's own associations" do
    tenant = create(:tenant)
    widget = create(:widget, tenant: tenant)
    gadget = create(:gadget, tenant: tenant)

    TenancyDable.with_tenant(tenant) do
      expect(tenant.widgets.to_a).to eq([widget])
      expect(tenant.first_widget).to eq(widget)
      expect(tenant.gadgets.to_a).to eq([gadget])
      expect(widget.children.to_a).to be_empty
    end
  end
end
