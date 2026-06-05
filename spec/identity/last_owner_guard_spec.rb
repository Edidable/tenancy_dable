# frozen_string_literal: true

require "rails_helper"

# Last-owner-demotion guard (DESIGN.md §6.2). A `before_update` refuses to demote
# the ONLY owner of a tenant — otherwise a workspace could be left ownerless. It
# halts via `throw :abort`: the save returns false (or `update!` raises), the
# record carries a validation error, and the database row is unchanged. Demoting
# one of several owners, or touching a non-owner membership, is allowed. The
# guard is `before_update` only, so it is the system-under-test here.
RSpec.describe "TenancyDable::MembershipModel — last-owner guard" do
  describe "demoting the only owner of a tenant" do
    it "is blocked: the save returns false and the row is unchanged" do
      tenant = create(:tenant)
      owner = create(:membership, tenant: tenant, role: "owner")

      result = owner.update(role: "member")

      expect(result).to be(false)
      expect(owner.errors[:role]).to be_present
      expect(owner.reload.role).to eq("owner")
    end

    it "raises ActiveRecord::RecordNotSaved on the bang variant" do
      tenant = create(:tenant)
      owner = create(:membership, tenant: tenant, role: "owner")

      expect { owner.update!(role: "member") }
        .to raise_error(ActiveRecord::RecordNotSaved)
      expect(owner.reload.role).to eq("owner")
    end

    it "blocks demotion to any non-owner role" do
      tenant = create(:tenant)
      owner = create(:membership, tenant: tenant, role: "owner")

      expect(owner.update(role: "admin")).to be(false)
      expect(owner.reload.role).to eq("owner")
    end

    it "checks only the membership's own tenant for other owners" do
      tenant_a = create(:tenant)
      tenant_b = create(:tenant)
      owner_a = create(:membership, tenant: tenant_a, role: "owner")
      # An owner of a DIFFERENT tenant must not count toward tenant_a's owners.
      create(:membership, tenant: tenant_b, role: "owner")

      expect(owner_a.update(role: "member")).to be(false)
      expect(owner_a.reload.role).to eq("owner")
    end
  end

  describe "demoting an owner when another owner remains" do
    it "succeeds and persists the new role" do
      tenant = create(:tenant)
      owner = create(:membership, tenant: tenant, role: "owner")
      create(:membership, tenant: tenant, role: "owner") # a second, distinct owner

      result = owner.update(role: "member")

      expect(result).to be(true)
      expect(owner.reload.role).to eq("member")
    end
  end

  describe "changes the guard does not touch" do
    it "allows editing a non-owner membership even when the tenant has a single owner" do
      tenant = create(:tenant)
      create(:membership, tenant: tenant, role: "owner") # the lone owner, untouched
      member = create(:membership, tenant: tenant, role: "member")

      expect(member.update(role: "admin")).to be(true)
      expect(member.reload.role).to eq("admin")
    end

    it "allows promoting a member to owner" do
      tenant = create(:tenant)
      create(:membership, tenant: tenant, role: "owner")
      member = create(:membership, tenant: tenant, role: "member")

      expect(member.update(role: "owner")).to be(true)
      expect(member.reload.role).to eq("owner")
    end
  end
end
