# frozen_string_literal: true

require "rails_helper"

# TenancyDable::Channel end-to-end through a real Action Cable channel
# (TenantChannel) — the Cable parallel to the controller resolution specs
# (spec/resolution/*). `stub_connection(current_user:)` injects the HOST-owned
# connection identity (the gem never establishes it — guardrail);
# `subscribe(tenant_slug:)` drives `#subscribed`; `perform` routes an action
# through the concern's `perform_action` wrap, which is the auto-context seam.
RSpec.describe TenantChannel, type: :channel do
  describe "#subscribed — slug resolution + membership enforcement" do
    it "subscribes a member and streams the tenant-namespaced stream" do
      tenant = create(:tenant, slug: "acme")
      user = create(:user)
      create(:membership, user: user, tenant: tenant, role: "member")

      stub_connection(current_user: user)
      subscribe(tenant_slug: "acme")

      expect(subscription).to be_confirmed
      # Stream name is "tenant:<id>" (slug-resolved, id-namespaced) — never a
      # cross-tenant stream and never keyed off the slug.
      expect(subscription).to have_stream_from("tenant:#{tenant.id}")
    end

    it "rejects a non-member of the resolved tenant" do
      create(:tenant, slug: "acme")
      stub_connection(current_user: create(:user)) # authenticated, member of nothing

      subscribe(tenant_slug: "acme")

      expect(subscription).to be_rejected
    end

    it "rejects a user who is a member of a DIFFERENT tenant" do
      create(:tenant, slug: "acme")
      other = create(:tenant, slug: "other")
      user = create(:user)
      create(:membership, user: user, tenant: other, role: "owner") # owner — but elsewhere

      stub_connection(current_user: user)
      subscribe(tenant_slug: "acme")

      expect(subscription).to be_rejected
    end

    it "rejects an unknown slug (no tenant ⇒ not a member)" do
      stub_connection(current_user: create(:user))

      subscribe(tenant_slug: "does-not-exist")

      expect(subscription).to be_rejected
    end

    it "rejects a tenant's numeric id placed in the slug slot (slug-only — invariant 5)" do
      # The Cable path resolves BY SLUG only (DESIGN §9.1); a real tenant's own id
      # dropped into the slug param must NOT resolve it — `find_by(slug:)` won't
      # match an id — so even its own member, asking by id instead of slug, is
      # rejected. The Cable parallel to spec/resolution/slug_only_spec.rb, proving
      # the URL-id-injection vector is closed on the new channel path too.
      tenant = create(:tenant, slug: "acme")
      member = create(:user)
      create(:membership, user: member, tenant: tenant, role: "member")

      stub_connection(current_user: member)
      subscribe(tenant_slug: tenant.id.to_s)

      expect(subscription).to be_rejected
    end

    it "rejects an absent slug (nil tenant ⇒ not a member)" do
      stub_connection(current_user: create(:user))

      subscribe # no subscription params at all

      expect(subscription).to be_rejected
    end
  end

  describe "channel actions — automatic tenant context (perform_action wrap)" do
    # Two tenants with widgets in BOTH; the acting user is a member of A only, so
    # the action's scoped read must see A's rows and never B's.
    let(:tenant_a) { create(:tenant, slug: "alpha") }
    let(:tenant_b) { create(:tenant, slug: "bravo") }
    let(:member_a) { create(:user) }

    before do
      create(:membership, user: member_a, tenant: tenant_a, role: "member")
      create(:widget, tenant: tenant_a, name: "A-1")
      create(:widget, tenant: tenant_a, name: "A-2")
      create(:widget, tenant: tenant_b, name: "B-1") # cross-tenant noise

      stub_connection(current_user: member_a)
      subscribe(tenant_slug: "alpha")
    end

    it "runs the action inside the subscription's tenant context" do
      perform :widget_count

      # tenant_id transmitted from INSIDE the action == the subscription's tenant,
      # proving the wrap set TenancyDable.current_tenant during dispatch.
      expect(transmissions.last["tenant_id"]).to eq(tenant_a.id)
    end

    it "scopes a read to the acting tenant — cross-tenant rows are invisible" do
      perform :widget_count

      # Unscoped here (context already torn down) the table holds 3 widgets
      # (2 in A + 1 in B); the read INSIDE the action saw only A's two.
      expect(Widget.count).to eq(3)
      expect(transmissions.last["widget_count"]).to eq(2)
    end

    it "does not leak the tenant context after the action (CurrentAttributes reset)" do
      perform :widget_count

      # with_tenant's ensure restores the prior (nil) tenant + membership, so a
      # pooled connection thread never carries one action's context into the next.
      expect(TenancyDable.current_tenant).to be_nil
      expect(TenancyDable.current_membership).to be_nil
    end
  end
end
