# frozen_string_literal: true

require "rails_helper"

# Resolution + authorization composed end-to-end (DESIGN §9; invariants 2 & 4).
# A request to `/:tenant_slug/reports` resolves the workspace from the slug,
# enforces membership, and — in the SAME request — renders the ids the Pundit
# `Policy::Base::Scope` exposes (see ReportsController). Two facts must hold
# together:
#   * a member of A reaching A's slug sees ONLY A's rows — the policy scope filters
#     to the resolved tenant and never leaks another tenant's rows;
#   * a member of B reaching A's slug is REJECTED at resolution (NotAMemberError),
#     so the policy layer is never even consulted for an outsider.
RSpec.describe "Integration: resolution + policy scope", type: :request do
  # Re-raise (Rails 8.1 `:none`) so the rejection path surfaces the EXACT error
  # class instead of a rendered 500; restored after every example. The happy-path
  # examples never raise, so the override is inert for them. (Same rationale as the
  # resolution specs.)
  around do |example|
    env = Rails.application.env_config
    key = "action_dispatch.show_exceptions"
    original = env[key]
    env[key] = :none
    example.run
  ensure
    env[key] = original
  end

  # Auth-agnostic acting user, captured in a LOCAL the resolver lambda closes over
  # (Resolvable runs it with instance_exec, rebinding self). See the resolution
  # specs for the full rationale.
  def act_as(user)
    acting_user = user
    TenancyDable.configuration.current_user_resolver = -> { acting_user }
  end

  let(:tenant_a) { create(:tenant, slug: "alpha") }
  let(:tenant_b) { create(:tenant, slug: "bravo") }
  let(:member_a) { create(:user) }
  let(:member_b) { create(:user) }

  before do
    create(:membership, user: member_a, tenant: tenant_a, role: "owner")
    create(:membership, user: member_b, tenant: tenant_b, role: "owner")
  end

  it "renders only the resolved tenant's rows for a member of that tenant" do
    a1 = create(:widget, tenant: tenant_a, name: "A-1")
    a2 = create(:widget, tenant: tenant_a, name: "A-2")
    _b1 = create(:widget, tenant: tenant_b, name: "B-1")
    act_as(member_a)

    get "/alpha/reports"

    expect(response).to have_http_status(:ok)
    # Body is the policy-scoped ids; B's row is absent.
    expect(response.body).to eq([a1.id, a2.id].sort.join(","))
  end

  it "never leaks another tenant's rows through the policy scope" do
    create(:widget, tenant: tenant_b, name: "B-only")
    act_as(member_a)

    get "/alpha/reports"

    # A owns no widgets; the policy scope resolves to A's (empty) set, NOT B's row.
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("")
  end

  it "rejects a member of B reaching A's slug before the policy is ever consulted" do
    create(:widget, tenant: tenant_a, name: "A-secret")
    act_as(member_b) # owner of B, member of NOTHING in A

    expect { get "/alpha/reports" }.to raise_error(TenancyDable::NotAMemberError)
  end
end
