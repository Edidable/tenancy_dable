# frozen_string_literal: true

require "rails_helper"

# `Policy::Base::Scope#resolve` is the Pundit `policy_scope` half of isolation
# (DESIGN.md §9.3, security invariant 4). Its contract:
#
#   * tenant nil -> `scope.none`  — FAIL CLOSED: with no active tenant, expose
#     NOTHING, never every tenant's rows;
#   * tenant set -> `scope.where(config.tenant_fk => tenant.id)` — filter to the
#     active tenant, excluding other tenants' rows.
#
# Every example runs inside `without_tenant` so `Widget`'s own tenant
# default-scope is bypassed (resolves to `all`). That makes the POLICY scope the
# ONLY filter in play: an empty result is provably `Scope#resolve` returning
# `.none`, and a filtered result is provably its `where`, neither masked by the
# model's default scope.
RSpec.describe "TenancyDable::Policy::Base::Scope#resolve" do
  let(:scope_class) { TenancyDable::Policy::Base::Scope }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  # Scope only reads `context.tenant`; membership is irrelevant to resolution.
  def context_for(tenant)
    TenancyDable.pundit_context(user: build(:user), tenant: tenant, membership: nil)
  end

  it "fails closed: resolves to scope.none when there is no active tenant" do
    # Rows from both tenants exist and are visible to the bypassed model scope,
    # so an empty result can only be the policy scope's `.none`.
    create(:widget, tenant: tenant_a)
    create(:widget, tenant: tenant_b)

    resolved = TenancyDable.without_tenant do
      scope_class.new(context_for(nil), Widget.all).resolve.to_a
    end

    expect(resolved).to be_empty
  end

  it "filters the scope to the active tenant's rows" do
    mine = create(:widget, tenant: tenant_a)

    resolved = TenancyDable.without_tenant do
      scope_class.new(context_for(tenant_a), Widget.all).resolve.to_a
    end

    expect(resolved).to contain_exactly(mine)
  end

  it "excludes other tenants' rows" do
    mine = create(:widget, tenant: tenant_a)
    _theirs = create(:widget, tenant: tenant_b)

    resolved = TenancyDable.without_tenant do
      scope_class.new(context_for(tenant_a), Widget.all).resolve.to_a
    end

    expect(resolved).to contain_exactly(mine)
    expect(resolved.map(&:tenant_id)).to all(eq(tenant_a.id))
  end
end
