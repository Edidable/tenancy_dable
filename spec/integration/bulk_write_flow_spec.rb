# frozen_string_literal: true

require "rails_helper"

# Bulk-write guard surfacing in a realistic operational flow (DESIGN §5.2;
# invariant 2). `update_all` / `delete_all` skip the default scope's WHERE, so an
# admin task that forgets to establish the tenant would otherwise rewrite EVERY
# workspace's rows in one statement. The guard turns that into a loud
# `BulkWriteError` with nothing written; once the tenant is active, the same call
# succeeds and touches only that tenant's rows.
RSpec.describe "Integration: bulk-write guard in a realistic flow" do
  let(:tenant_a) { create(:tenant, slug: "alpha") }
  let(:tenant_b) { create(:tenant, slug: "bravo") }

  let!(:widget_a) { create(:widget, tenant: tenant_a, name: "A-keep") }
  let!(:widget_b) { create(:widget, tenant: tenant_b, name: "B-keep") }

  it "blocks a mass update that forgot to scope to a tenant, writing nothing" do
    expect {
      Widget.update_all(name: "rebranded")
    }.to raise_error(TenancyDable::BulkWriteError)

    # Both tenants' rows are untouched — the guard fired BEFORE any SQL ran.
    expect(widget_a.reload.name).to eq("A-keep")
    expect(widget_b.reload.name).to eq("B-keep")
  end

  it "permits the same mass update once a tenant is active, touching only its rows" do
    TenancyDable.with_tenant(tenant_a) do
      expect { Widget.update_all(name: "rebranded") }.not_to raise_error
    end

    expect(widget_a.reload.name).to eq("rebranded") # A's row changed
    expect(widget_b.reload.name).to eq("B-keep")    # B's row left alone (invariant 2)
  end

  it "still blocks a relation explicitly aimed at another tenant" do
    TenancyDable.with_tenant(tenant_a) do
      expect {
        Widget.unscoped.where(tenant_id: tenant_b.id).delete_all
      }.to raise_error(TenancyDable::BulkWriteError)
    end

    expect(widget_b.reload.name).to eq("B-keep") # B's row survives the cross-tenant attempt
  end

  it "lets an explicit without_tenant override sweep across all tenants" do
    TenancyDable.without_tenant do
      expect { Widget.update_all(name: "swept") }.not_to raise_error
    end

    # The deliberate bypass is the documented escape hatch for genuine cross-tenant
    # maintenance — both rows change.
    expect(widget_a.reload.name).to eq("swept")
    expect(widget_b.reload.name).to eq("swept")
  end
end
