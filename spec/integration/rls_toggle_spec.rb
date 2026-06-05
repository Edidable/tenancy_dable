# frozen_string_literal: true

require "rails_helper"

# Row-Level-Security toggle, end-to-end on tenant switch (DESIGN §4.2; PLAN config
# `rls`). `current_tenant=` is the single mutation path; when `config.rls` is on
# it emits `config.rls_statement.call(tenant)` against the AR connection every
# time the effective tenant changes (entry AND restore), and when off it emits
# nothing. We spy on the connection (SQLite has no real `SET app.*`) and use a
# harmless SELECT carrying a marker so the spy can pass through to the real
# `execute` — keeping the per-example transaction rollback intact.
RSpec.describe "Integration: RLS toggle on tenant switch" do
  let(:tenant_a) { create(:tenant, slug: "alpha") }
  let(:tenant_b) { create(:tenant, slug: "bravo") }
  let(:connection) { ActiveRecord::Base.connection }

  # The spy passes execute through to SQLite (`and_call_original`), so the marker
  # statement must be VALID SQL for every tenant — including the nil the final
  # restore sets (mirroring the gem's nil-safe default). `SELECT <id>` / `SELECT
  # NULL` are harmless no-op reads that leave the per-example transaction intact.
  def enable_rls!
    TenancyDable.configure do |c|
      c.rls = true
      c.rls_statement = ->(t) { "SELECT #{t&.id || "NULL"} -- tenancy_dable rls" }
    end
  end

  it "runs the rls_statement on each tenant switch when enabled" do
    enable_rls!
    allow(connection).to receive(:execute).and_call_original

    TenancyDable.with_tenant(tenant_a) { Widget.count }
    TenancyDable.with_tenant(tenant_b) { Widget.count }

    expect(connection).to have_received(:execute)
      .with("SELECT #{tenant_a.id} -- tenancy_dable rls").at_least(:once)
    expect(connection).to have_received(:execute)
      .with("SELECT #{tenant_b.id} -- tenancy_dable rls").at_least(:once)
  end

  it "re-fires on restore so an enabled RLS session never stays pointed at an inner tenant" do
    enable_rls!
    allow(connection).to receive(:execute).and_call_original

    TenancyDable.with_tenant(tenant_a) do
      TenancyDable.with_tenant(tenant_b) { :inner }
      # Leaving the inner block must re-point RLS back at A before more A-scoped
      # work runs — otherwise the session variable would still say "B".
    end

    # A's statement ran on entry AND again on restore-from-B: twice. That second
    # fire is the cross-tenant-leak guard the with_tenant ensure exists for.
    expect(connection).to have_received(:execute)
      .with("SELECT #{tenant_a.id} -- tenancy_dable rls").twice
  end

  it "does not touch the connection with an rls_statement when disabled (default)" do
    expect(TenancyDable.configuration.rls).to be(false)
    allow(connection).to receive(:execute).and_call_original

    TenancyDable.with_tenant(tenant_a) { Widget.count }

    expect(connection).not_to have_received(:execute)
      .with(a_string_including("tenancy_dable rls"))
  end
end
