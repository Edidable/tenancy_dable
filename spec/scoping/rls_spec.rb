# frozen_string_literal: true

require "rails_helper"

# Row-Level-Security hook (DESIGN.md §4.2). `current_tenant=` is the single
# mutation path; when `config.rls` is truthy and the effective tenant changes it
# emits `config.rls_statement.call(tenant)` against the AR connection. We spy on
# the connection rather than execute real RLS SQL (SQLite has no `SET app.*`),
# and use a harmless custom statement so the spy can pass through to the real
# `execute` — keeping the per-example transaction rollback intact.
RSpec.describe "TenancyDable RLS hook" do
  let(:tenant_a) { create(:tenant) }

  it "executes the configured rls_statement on the connection when rls is enabled" do
    TenancyDable.configure do |c|
      c.rls = true
      c.rls_statement = ->(t) { "SELECT #{t.id} -- tenancy_dable rls" }
    end
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:execute).and_call_original

    TenancyDable.current_tenant = tenant_a

    expect(connection).to have_received(:execute)
      .with("SELECT #{tenant_a.id} -- tenancy_dable rls")
  end

  it "does not touch the connection's RLS statement when rls is disabled (default)" do
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:execute).and_call_original

    expect(TenancyDable.configuration.rls).to be(false)
    TenancyDable.current_tenant = tenant_a

    expect(connection).not_to have_received(:execute)
      .with(a_string_starting_with("SET app.tenant_id"))
  end

  it "builds a `SET app.tenant_id = <id>` statement by default" do
    statement = TenancyDable.configuration.rls_statement.call(tenant_a)

    expected = "SET app.tenant_id = #{ActiveRecord::Base.connection.quote(tenant_a.id)}"
    expect(statement).to eq(expected)
  end
end
