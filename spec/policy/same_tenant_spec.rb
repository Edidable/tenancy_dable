# frozen_string_literal: true

require "rails_helper"

# `same_tenant?` is the per-record half of cross-tenant defense (DESIGN.md §9.3,
# §10-C, security invariant 2): a concrete policy pairs it with a capability so a
# manager of tenant A still cannot mutate a row owned by tenant B. The helper is
# `record.respond_to?(:tenant_id) && record.tenant_id == tenant&.id`, so:
#
#   * true ONLY when the record's tenant_id equals the acting tenant's id;
#   * false across tenants;
#   * false when there is no acting tenant (tenant nil), even for a record that
#     carries a tenant_id — fail closed;
#   * false (never raises) on a record with no tenant_id at all — the guard keeps
#     the helper safe on non-scoped records so any policy may call it blindly.
#
# `same_tenant?` is PRIVATE on `Base` (so Pundit/pundit-matchers never treat it
# as an action — DESIGN.md §10-D); a thin subclass re-publicizes it UNDER ITS
# REAL NAME purely to exercise the helper in isolation.
RSpec.describe "TenancyDable::Policy::Base#same_tenant?" do
  # Subclass that exposes the inherited private helper without renaming it.
  let(:probe_class) do
    Class.new(TenancyDable::Policy::Base) { public :same_tenant? }
  end

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }

  def probe_for(context_tenant, record)
    context = TenancyDable.pundit_context(
      user: build(:user),
      tenant: context_tenant,
      membership: build(:membership, role: "owner")
    )
    probe_class.new(context, record)
  end

  it "is true when the record belongs to the acting tenant" do
    record = create(:widget, tenant: tenant)

    expect(probe_for(tenant, record).same_tenant?).to be(true)
  end

  it "is false when the record belongs to a different tenant" do
    foreign_record = create(:widget, tenant: other_tenant)

    expect(probe_for(tenant, foreign_record).same_tenant?).to be(false)
  end

  it "is false when there is no acting tenant, even for a record with a tenant_id" do
    record = create(:widget, tenant: tenant)

    expect(probe_for(nil, record).same_tenant?).to be(false)
  end

  it "is false (does not raise) on a record that carries no tenant_id" do
    non_scoped_record = Object.new
    expect(non_scoped_record).not_to respond_to(:tenant_id)

    expect { probe_for(tenant, non_scoped_record).same_tenant? }.not_to raise_error
    expect(probe_for(tenant, non_scoped_record).same_tenant?).to be(false)
  end
end
