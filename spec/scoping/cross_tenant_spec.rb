# frozen_string_literal: true

require "rails_helper"

# Cross-tenant belongs_to validation (DESIGN.md §5.1, invariant 2). A
# tenant-scoped association (here Widget's self-referential `parent`) must point
# at a record in the SAME tenant; pointing at another tenant's row adds a
# validation error. The target is read `unscoped`, so the breach is detected
# even when the current tenant's default scope would otherwise hide it.
RSpec.describe "TenancyDable::Scoped — cross-tenant belongs_to validation" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  it "accepts an association whose target is in the same tenant" do
    parent = create(:widget, tenant: tenant_a)
    child = build(:widget, tenant: tenant_a, parent: parent)

    expect(child).to be_valid
  end

  it "rejects an association whose target belongs to a different tenant" do
    parent_in_b = create(:widget, tenant: tenant_b)
    child = build(:widget, tenant: tenant_a, parent: parent_in_b)

    expect(child).not_to be_valid
    expect(child.errors[:parent]).to include("belongs to a different tenant")
  end

  it "detects the breach even when the current tenant would hide the target" do
    # parent_in_b lives in tenant B; with tenant A current, a scoped read could
    # not see it — but the validation reads `unscoped` on purpose (invariant 2).
    parent_in_b = create(:widget, tenant: tenant_b)
    TenancyDable.current_tenant = tenant_a

    child = build(:widget, tenant: tenant_a, parent: parent_in_b)

    expect(child).not_to be_valid
    expect(child.errors[:parent]).to include("belongs to a different tenant")
  end
end
