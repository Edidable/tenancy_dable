# frozen_string_literal: true

require "rails_helper"

# MembershipModel validations (DESIGN.md §6.2):
#
#   * `role` must be one of `config.roles` (the `in:` set is a callable, so it is
#     read at validation time — a reconfigured role set is honored live);
#   * `[user_id, tenant_id]` is unique — a user holds at most one membership per
#     workspace, but the same user may join many workspaces and a workspace may
#     have many users.
#
# Uniqueness is asserted at the MODEL level (`build` + `valid?`): the schema also
# carries a DB unique index, but the model validation is the system-under-test,
# so we never let the duplicate reach the database.
RSpec.describe "TenancyDable::MembershipModel — validations" do
  describe "role inclusion" do
    it "accepts each configured role" do
      TenancyDable.configuration.roles.each do |role_name|
        expect(build(:membership, role: role_name)).to be_valid
      end
    end

    it "rejects a role outside config.roles" do
      membership = build(:membership, role: "superuser")

      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to include("is not included in the list")
    end

    it "rejects a blank role" do
      membership = build(:membership, role: nil)

      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to be_present
    end

    it "honors a reconfigured role set at validation time" do
      # The `in:` set is a callable evaluated per-validation, so a role that is
      # invalid under the default config becomes valid once configured in.
      TenancyDable.configure do |c|
        c.roles = %w[owner admin member guest]
        c.manager_roles = %w[owner admin]
      end

      expect(build(:membership, role: "guest")).to be_valid
    end
  end

  describe "[user_id, tenant_id] uniqueness" do
    it "rejects a second membership for the same user in the same tenant" do
      user = create(:user)
      tenant = create(:tenant)
      create(:membership, user: user, tenant: tenant, role: "member")

      duplicate = build(:membership, user: user, tenant: tenant, role: "admin")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end

    it "allows the same user to be a member of a different tenant" do
      user = create(:user)
      create(:membership, user: user, tenant: create(:tenant), role: "member")

      other = build(:membership, user: user, tenant: create(:tenant), role: "owner")

      expect(other).to be_valid
    end

    it "allows a different user to join the same tenant" do
      tenant = create(:tenant)
      create(:membership, user: create(:user), tenant: tenant, role: "owner")

      other = build(:membership, user: create(:user), tenant: tenant, role: "member")

      expect(other).to be_valid
    end
  end
end
