# frozen_string_literal: true

require "rails_helper"
require "pundit" # so `Pundit::NotAuthorizedError` resolves when the matcher is built

# Host-selectable not-a-member behavior (v0.2.0; DESIGN §4.1 / §9.1 step 3).
# `config.on_not_a_member` chooses what resolution does when the acting user is
# authenticated but NOT a member of the resolved tenant. The DEFAULT preserves
# v0.1.0 behavior (raise `NotAMemberError`); a host may instead raise Pundit's
# `NotAuthorizedError` (to reuse an existing `rescue_from`) or hand control to its
# own callable. Membership stays REQUIRED in every mode — a non-member never gets
# a published tenant (security invariant 2); only the FAILURE shape is selectable.
RSpec.describe "TenancyDable::Controller::Resolvable — on_not_a_member", type: :request do
  # As in membership_enforcement_spec: assert the raised error directly with
  # `show_exceptions = :none` rather than via an HTTP status (a 500 would not
  # prove WHICH error was raised). Harmless for the non-raising callable mode.
  around do |example|
    env = Rails.application.env_config
    key = "action_dispatch.show_exceptions"
    original = env[key]
    env[key] = :none
    example.run
  ensure
    env[key] = original
  end

  # Auth-agnostic acting user, captured in a local so the resolver resolves the
  # same record regardless of the controller `self` it is `instance_exec`'d in.
  def act_as(user)
    acting_user = user
    TenancyDable.configuration.current_user_resolver = -> { acting_user }
  end

  # A real workspace with an authenticated NON-member acting against it — the
  # exact precondition every mode below branches on. (rails_helper's global
  # `after` resets the configuration, so each per-example mode override is undone.)
  def request_as_non_member
    create(:tenant, slug: "acme")
    act_as(create(:user)) # authenticated, but a member of nothing
    get "/acme/widgets"
  end

  describe ":not_a_member_error (default)" do
    it "raises TenancyDable::NotAMemberError out of the box" do
      # No override — pins that the new setting's default preserves v0.1.0 behavior.
      create(:tenant, slug: "acme")
      act_as(create(:user))

      expect { get "/acme/widgets" }.to raise_error(TenancyDable::NotAMemberError)
    end
  end

  describe ":not_authorized" do
    it "raises Pundit::NotAuthorizedError instead" do
      TenancyDable.configuration.on_not_a_member = :not_authorized
      create(:tenant, slug: "acme")
      act_as(create(:user))

      expect { get "/acme/widgets" }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  describe "a callable" do
    it "runs in the controller's context with the resolved tenant, and its outcome wins" do
      received_tenant = nil
      TenancyDable.configuration.on_not_a_member = lambda do |tenant|
        received_tenant = tenant
        head :forbidden # a controller method — resolvable only if `self` is the controller
      end

      request_as_non_member

      # The callable's `head :forbidden` halted the before_action, so the action's
      # own render never ran — its outcome (403) won over the default raise.
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("role:")
      # ...and it received the RESOLVED tenant as its sole argument.
      expect(received_tenant.slug).to eq("acme")
    end

    it "may raise its own error, which propagates" do
      host_error = Class.new(StandardError)
      TenancyDable.configuration.on_not_a_member = ->(_tenant) { raise host_error, "host says no" }

      create(:tenant, slug: "acme")
      act_as(create(:user))

      expect { get "/acme/widgets" }.to raise_error(host_error, "host says no")
    end
  end

  it "still admits a genuine member regardless of the configured mode (contrast)" do
    # The setting governs ONLY the non-member branch; a real member is unaffected.
    TenancyDable.configuration.on_not_a_member = :not_authorized
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "member")
    act_as(user)

    expect { get "/acme/widgets" }.not_to raise_error
    expect(response.body).to eq("tenant:acme role:member")
  end
end
