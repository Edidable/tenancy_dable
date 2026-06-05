# frozen_string_literal: true

require "rails_helper"

# Unknown slug → `on_tenant_not_found` (DESIGN.md §9.1 / §10-A; PLAN config
# table). The lookup is `find_by!(slug:)` under `:raise` (the default) and
# `find_by(slug:)` under `:null`, so the two strategies diverge precisely on a
# miss:
#   :raise → ActiveRecord::RecordNotFound  (NOT TenantNotFoundError — see §10-A:
#            the find_by! bang path raises AR's own error; TenantNotFoundError
#            stays reserved for host/non-bang strategies)
#   :null  → nil tenant; the request proceeds workspace-less
RSpec.describe "TenancyDable::Controller::Resolvable — unknown slug", type: :request do
  # Combustion boots with `show_exceptions` left truthy, so a raised error would
  # be RENDERED as an HTTP page (404/500) and never reach the example. Flip it to
  # Rails 8.1's `:none` ("re-raise") so we can assert the EXACT class the
  # before_action raises; restored after every example. The :null examples never
  # raise, so the override is inert for them.
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

  context "with the default :raise strategy" do
    it "raises ActiveRecord::RecordNotFound" do
      # The tenant lookup fails FIRST, so this non-member acting user never even
      # reaches the membership branch — the matcher would fail on a NotAMemberError.
      act_as(create(:user))

      expect { get "/ghost/widgets" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "with the :null strategy" do
    before { TenancyDable.configure { |c| c.on_tenant_not_found = :null } }

    it "resolves to a nil tenant and proceeds workspace-less" do
      # No resolver stub needed: a null tenant short-circuits before the acting
      # user is ever resolved, so the action runs with a cleared context.
      get "/ghost/widgets"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("tenant: role:")
    end

    it "does not require membership when the tenant resolves to nil" do
      # A null tenant means "no workspace in context": there is nothing to be a
      # member of, so resolution must not raise NotAMemberError.
      expect { get "/ghost/widgets" }.not_to raise_error
    end
  end
end
