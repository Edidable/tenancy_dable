# frozen_string_literal: true

require "rails_helper"

# Slug resolution, the happy path (DESIGN.md §9.1; PLAN.md "Slug resolution").
# A request to `/:tenant_slug/...` whose acting user is a member of that
# workspace must, DURING the request, publish BOTH `TenancyDable.current_tenant`
# and `current_membership`. ActiveSupport::CurrentAttributes is reset the instant
# the response is sent, so the harness controller echoes what the before_action
# established into the body — that body is the only reliable observation channel
# (the after-request `nil`s in the last example are exactly why).
RSpec.describe "TenancyDable::Controller::Resolvable — successful resolution", type: :request do
  # The acting user is auth-agnostic. Resolvable runs `current_user_resolver`
  # with `instance_exec` in the CONTROLLER's context, which rebinds `self`; a
  # resolver leaning on implicit self (`-> { user }`) would dispatch `user` to
  # the controller and blow up. So we capture the record in a LOCAL the lambda
  # closes over — it resolves the same no matter what `self` is. This is the
  # whole mechanism by which a host wires its own auth stack into resolution.
  def act_as(user)
    acting_user = user
    TenancyDable.configuration.current_user_resolver = -> { acting_user }
  end

  it "publishes current_tenant and current_membership for a member" do
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "admin")
    act_as(user)

    get "/acme/widgets"

    expect(response).to have_http_status(:ok)
    # body == "tenant:<current_tenant.slug> role:<current_membership.role>"
    expect(response.body).to eq("tenant:acme role:admin")
  end

  it "resolves the ACTING user's own membership, not another member's" do
    tenant = create(:tenant, slug: "acme")
    actor = create(:user)
    create(:membership, user: actor, tenant: tenant, role: "owner")
    create(:membership, user: create(:user), tenant: tenant, role: "member") # same tenant, other user
    act_as(actor)

    get "/acme/widgets"

    # role:owner (the actor's), never role:member (the bystander's) — proof the
    # published membership is keyed to the acting user, not just the tenant.
    expect(response.body).to eq("tenant:acme role:owner")
  end

  it "clears the published context once the response is sent" do
    tenant = create(:tenant, slug: "acme")
    user = create(:user)
    create(:membership, user: user, tenant: tenant, role: "member")
    act_as(user)

    get "/acme/widgets"

    # The executor resets CurrentAttributes when the request finishes, so reading
    # the facade out here observes nothing — which is *why* the assertions above
    # read the response body instead of the live `current_*` accessors.
    expect(TenancyDable.current_tenant).to be_nil
    expect(TenancyDable.current_membership).to be_nil
  end
end
