# frozen_string_literal: true

require "rails_helper"

# UserModel membership lookups (DESIGN.md §6.3). These are the entry points
# `Resolvable` uses to answer "is this user a member of this workspace, and as
# what?" — and they run BEFORE any tenant is current, which is why Membership is
# not tenant-scoped (DESIGN.md §5.3). Both lookups are nil-safe: a nil tenant or
# a non-member tenant yields nil / false rather than raising.
RSpec.describe "TenancyDable::UserModel — membership lookups" do
  let(:user) { create(:user) }
  let(:tenant) { create(:tenant) }

  describe "#membership_for" do
    it "returns the user's membership in the tenant" do
      membership = create(:membership, user: user, tenant: tenant, role: "admin")

      expect(user.membership_for(tenant)).to eq(membership)
    end

    it "returns nil when the user is not a member of the tenant" do
      other_tenant = create(:tenant)
      create(:membership, user: user, tenant: tenant) # member of `tenant`, not `other_tenant`

      expect(user.membership_for(other_tenant)).to be_nil
    end

    it "returns nil for a user with no memberships at all" do
      expect(user.membership_for(tenant)).to be_nil
    end

    it "returns nil for a nil tenant" do
      expect(user.membership_for(nil)).to be_nil
    end

    it "is scoped to the receiver — it never returns another user's membership" do
      other_user = create(:user)
      create(:membership, user: other_user, tenant: tenant, role: "owner")

      expect(user.membership_for(tenant)).to be_nil
    end
  end

  describe "#member_of?" do
    it "is true when the user has a membership in the tenant" do
      create(:membership, user: user, tenant: tenant)

      expect(user.member_of?(tenant)).to be(true)
    end

    it "is false when the user is not a member of the tenant" do
      other_tenant = create(:tenant)
      create(:membership, user: user, tenant: tenant)

      expect(user.member_of?(other_tenant)).to be(false)
    end

    it "is false for a user with no memberships at all" do
      expect(user.member_of?(tenant)).to be(false)
    end

    it "is false for a nil tenant" do
      expect(user.member_of?(nil)).to be(false)
    end
  end
end
