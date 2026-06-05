# frozen_string_literal: true

require "rails_helper"

# `Policy::Context` is the authorization subject every policy decides on: the
# acting user PLUS the workspace and the membership tying them together
# (DESIGN.md §9.2). It is a pure `Data` value with one derived attribute,
# `#role`, the single source of truth for "what role is acting" — `Base#role`
# delegates here.
#
# The contract for `#role` (DESIGN.md §9.2): read the role off the membership,
# and yield `nil` when there is no membership (a non-member, or no tenant in
# context) so every downstream capability helper fails closed for a nil role.
RSpec.describe "TenancyDable::Policy::Context#role" do
  it "derives the acting role from the membership" do
    context = TenancyDable.pundit_context(
      user: build(:user),
      tenant: build(:tenant),
      membership: build(:membership, role: "admin")
    )

    expect(context.role).to eq("admin")
  end

  it "tracks whatever role the membership carries" do
    TenancyDable.configuration.roles.each do |role_name|
      context = TenancyDable.pundit_context(
        user: build(:user),
        tenant: build(:tenant),
        membership: build(:membership, role: role_name)
      )

      expect(context.role).to eq(role_name)
    end
  end

  it "yields a nil role when there is no membership (non-member / no tenant)" do
    context = TenancyDable.pundit_context(
      user: build(:user),
      tenant: build(:tenant),
      membership: nil
    )

    expect(context.role).to be_nil
  end

  it "is the same triple regardless of how it is built (facade == Context.new)" do
    user = build(:user)
    tenant = build(:tenant)
    membership = build(:membership, role: "member")

    via_facade = TenancyDable.pundit_context(user: user, tenant: tenant, membership: membership)
    via_data = TenancyDable::Policy::Context.new(user: user, tenant: tenant, membership: membership)

    expect(via_facade).to eq(via_data)
    expect(via_facade.role).to eq("member")
  end
end
