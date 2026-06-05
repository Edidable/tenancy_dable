# frozen_string_literal: true

require "rails_helper"

# Slug-only resolution (security invariant 5; DESIGN.md §9.1). Resolution reads
# `params[slug_param]` and looks the tenant up by `slug` — it NEVER reads or
# trusts a tenant *id* from the URL. So a numeric id sitting in the slug position
# opens no id-based read path into a workspace: it simply fails to resolve,
# exactly as any other non-matching string would. This is the structural reason
# an attacker cannot enumerate workspaces by guessing sequential ids.
RSpec.describe "TenancyDable::Controller::Resolvable — slug only, never id", type: :request do
  # `:none` so the :raise miss propagates and we can name the exact class; the
  # :null example never raises. (See tenant_not_found_spec for the full rationale.)
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

  it "does not resolve a tenant by its numeric id in the slug position" do
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "owner")
    act_as(user)

    # The acting user IS an owner of this very tenant; the ONLY thing "wrong" is
    # that the URL carries the id instead of the slug. Under :raise that is a
    # plain RecordNotFound — find_by!(slug: "<id>") misses — proving there is no
    # id-lookup fallback to fall through to.
    expect { get "/#{tenant.id}/widgets" }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "treats a numeric id as just-another-missing-slug under :null" do
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "owner")
    act_as(user)
    TenancyDable.configure { |c| c.on_tenant_not_found = :null }

    get "/#{tenant.id}/widgets"

    # find_by(slug: "<id>") misses → nil tenant, NOT the tenant whose id matches.
    # A blank body (not "tenant:acme") is the proof no id lookup happened.
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("tenant: role:")
  end
end
