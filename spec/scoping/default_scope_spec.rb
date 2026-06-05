# frozen_string_literal: true

require "rails_helper"

# Default-scope behaviour of the scoping engine (DESIGN.md §5.1, invariant 1).
# Each example pins exactly one branch of the FROZEN decision tree:
#
#   if    Current.tenant_scope_disabled        -> all          (without_tenant bypass)
#   elsif current_tenant present               -> where(fk => current_tenant.id)
#   elsif require_tenant truthy-in-context     -> raise NoTenantError  (fail-closed)
#   else                                       -> all          (fail-open default)
#
# Fixtures are created with no current tenant (fail-open) so the factory's
# explicit tenant_id is the only thing that pins each row to a workspace; the
# reads under test then prove what the default scope filters.
RSpec.describe "TenancyDable::Scoped — default scope" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  it "filters reads to the current tenant and excludes other tenants' rows" do
    widget_a = create(:widget, tenant: tenant_a)
    _widget_b = create(:widget, tenant: tenant_b)

    visible = TenancyDable.with_tenant(tenant_a) { Widget.all.to_a }

    expect(visible).to contain_exactly(widget_a)
  end

  it "returns every row when require_tenant is falsy and no tenant is set (fail-open)" do
    widget_a = create(:widget, tenant: tenant_a)
    widget_b = create(:widget, tenant: tenant_b)

    expect(TenancyDable.current_tenant).to be_nil
    expect(TenancyDable.configuration.require_tenant).to be(false)
    expect(Widget.all.to_a).to contain_exactly(widget_a, widget_b)
  end

  it "raises NoTenantError when require_tenant is truthy and no tenant is set (fail-closed)" do
    TenancyDable.configure { |c| c.require_tenant = true }

    expect(TenancyDable.current_tenant).to be_nil
    expect { Widget.all.to_a }.to raise_error(TenancyDable::NoTenantError)
  end

  it "treats a callable require_tenant as truthy-in-context (fail-closed)" do
    TenancyDable.configure { |c| c.require_tenant = -> { true } }

    expect { Widget.all.to_a }.to raise_error(TenancyDable::NoTenantError)
  end

  it "bypasses the fail-closed guard inside without_tenant even when require_tenant is truthy" do
    # Build the row BEFORE flipping require_tenant on: once it is truthy, even
    # `Widget.new` would evaluate the fail-closed scope and raise.
    widget = create(:widget, tenant: tenant_a)
    TenancyDable.configure { |c| c.require_tenant = true }

    rows = TenancyDable.without_tenant { Widget.all.to_a }

    expect(rows).to include(widget)
  end

  it "disables scoping inside without_tenant and restores it after the block" do
    widget_a = create(:widget, tenant: tenant_a)
    widget_b = create(:widget, tenant: tenant_b)
    TenancyDable.current_tenant = tenant_a

    inside = TenancyDable.without_tenant { Widget.all.to_a }
    expect(inside).to contain_exactly(widget_a, widget_b) # bypass -> both tenants

    expect(Widget.all.to_a).to contain_exactly(widget_a) # restored -> only current
  end
end
