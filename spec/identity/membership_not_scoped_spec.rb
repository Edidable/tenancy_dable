# frozen_string_literal: true

require "rails_helper"

# Membership must NOT be tenant-scoped (DESIGN.md §5.3, the chicken/egg guard).
# It is queried to DISCOVER which tenants a user belongs to — `Resolvable` and
# `User#membership_for` hit it BEFORE any tenant is current — so applying the
# fail-closed tenant default scope to it would deadlock resolution. These
# examples pin that invariant from both sides: the structural marker the engine
# uses (`tenant_scoped?`) is absent, and the behavioral consequence (no
# fail-closed scope) holds even with `require_tenant` active.
#
# Widget — the scoped engine fixture — is the contrast throughout: whatever
# Membership must NOT do, Widget does.
RSpec.describe "TenancyDable::MembershipModel — deliberately not tenant-scoped" do
  it "does not declare itself tenant-scoped" do
    expect(Membership).not_to respond_to(:tenant_scoped?)

    # Contrast: a model that called belongs_to_tenant DOES carry the marker.
    expect(Widget).to respond_to(:tenant_scoped?)
    expect(Widget.tenant_scoped?).to be(true)
  end

  it "is queryable with no current tenant" do
    membership = create(:membership)

    expect(TenancyDable.current_tenant).to be_nil
    expect(Membership.all.to_a).to include(membership)
  end

  it "does not fail closed when require_tenant is active" do
    # Create the row BEFORE enabling require_tenant. Then, with no current tenant:
    # a scoped model fails closed (NoTenantError), but Membership must stay open —
    # resolution depends on reading it precisely when no tenant is established yet.
    membership = create(:membership)
    TenancyDable.configure { |c| c.require_tenant = true }

    expect(TenancyDable.current_tenant).to be_nil
    expect { Membership.all.to_a }.not_to raise_error
    expect { Widget.all.to_a }.to raise_error(TenancyDable::NoTenantError) # contrast
    expect(Membership.all.to_a).to include(membership)
  end

  it "ignores a current tenant entirely (returns memberships across tenants)" do
    tenant_a = create(:tenant)
    tenant_b = create(:tenant)
    membership_a = create(:membership, tenant: tenant_a)
    membership_b = create(:membership, tenant: tenant_b)

    # Even with tenant_a current, Membership has no default scope to filter by it.
    rows = TenancyDable.with_tenant(tenant_a) { Membership.all.to_a }

    expect(rows).to include(membership_a, membership_b)
  end
end
