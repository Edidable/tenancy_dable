# frozen_string_literal: true

require "rails_helper"

# Membership enforcement (DESIGN.md §9.1 step 3; security invariant 2). Resolving
# a real workspace is not enough — the acting user must be a MEMBER of THAT
# workspace, or resolution raises `NotAMemberError`. This is the gate that stops
# an authenticated-but-unauthorized user from reaching a workspace they have no
# membership in (and the reason a bare user id from the URL is never a read path).
RSpec.describe "TenancyDable::Controller::Resolvable — membership enforcement", type: :request do
  # See successful_resolution_spec for why the error path is asserted with
  # `show_exceptions = :none` rather than an HTTP status (500 would not prove the
  # error is specifically NotAMemberError).
  around do |example|
    env = Rails.application.env_config
    key = "action_dispatch.show_exceptions"
    original = env[key]
    env[key] = :none
    example.run
  ensure
    env[key] = original
  end

  def act_as(user)
    acting_user = user
    TenancyDable.configuration.current_user_resolver = -> { acting_user }
  end

  it "raises NotAMemberError when the acting user belongs to no workspace" do
    create(:tenant, slug: "acme")
    act_as(create(:user)) # authenticated, but a member of nothing

    expect { get "/acme/widgets" }.to raise_error(TenancyDable::NotAMemberError)
  end

  it "raises NotAMemberError when the user is a member of a DIFFERENT tenant" do
    create(:tenant, slug: "acme")
    other = create(:tenant, slug: "other")
    user = create(:user)
    create(:membership, user: user, tenant: other, role: "owner") # owner — but elsewhere
    act_as(user)

    expect { get "/acme/widgets" }.to raise_error(TenancyDable::NotAMemberError)
    # Sanity: they genuinely hold a (high) role somewhere; membership is checked
    # against the RESOLVED tenant, not "is a member of any tenant".
    expect(user.member_of?(other)).to be(true)
  end

  it "raises NotAMemberError when there is no acting user at all" do
    create(:tenant, slug: "acme")
    act_as(nil) # resolver returns nil → `user&.membership_for` is nil → raise

    expect { get "/acme/widgets" }.to raise_error(TenancyDable::NotAMemberError)
  end

  it "admits a genuine member of the resolved tenant (contrast)" do
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "member")
    act_as(user)

    expect { get "/acme/widgets" }.not_to raise_error
    expect(response.body).to eq("tenant:acme role:member")
  end
end
