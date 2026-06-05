# frozen_string_literal: true

require "rails_helper"

# TenantModel identity surface (DESIGN.md §6.1):
#
#   * `#owners` — the User records holding the highest role (`config.roles.first`)
#     in THIS tenant, via a subquery on the tenant's memberships;
#   * slug lifecycle — auto-generated from the name when blank (with a collision
#     suffix), and validated for presence, uniqueness, and URL-safe format.
#
# Slug examples create tenants WITHOUT the factory's sequenced slug (or override
# it) so `generate_slug` / the slug validations are the system-under-test.
RSpec.describe "TenancyDable::TenantModel" do
  describe "#owners" do
    it "returns the users who hold the owner role in the tenant" do
      tenant = create(:tenant)
      owner_user = create(:user)
      member_user = create(:user)
      create(:membership, user: owner_user, tenant: tenant, role: "owner")
      create(:membership, user: member_user, tenant: tenant, role: "member")

      expect(tenant.owners).to contain_exactly(owner_user)
    end

    it "returns every owner when a tenant has more than one" do
      tenant = create(:tenant)
      first = create(:user)
      second = create(:user)
      create(:membership, user: first, tenant: tenant, role: "owner")
      create(:membership, user: second, tenant: tenant, role: "owner")

      expect(tenant.owners).to contain_exactly(first, second)
    end

    it "excludes owners of other tenants" do
      tenant = create(:tenant)
      other_tenant = create(:tenant)
      mine = create(:user)
      theirs = create(:user)
      create(:membership, user: mine, tenant: tenant, role: "owner")
      create(:membership, user: theirs, tenant: other_tenant, role: "owner")

      expect(tenant.owners).to contain_exactly(mine)
    end

    it "is empty when the tenant has no owner" do
      tenant = create(:tenant)
      create(:membership, tenant: tenant, role: "member")

      expect(tenant.owners).to be_empty
    end
  end

  describe "slug auto-generation" do
    it "derives a URL-safe slug from the name when none is given" do
      tenant = Tenant.create!(name: "Acme Corp")

      expect(tenant.slug).to eq("acme-corp")
    end

    it "does not overwrite an explicitly supplied slug" do
      tenant = Tenant.create!(name: "Acme Corp", slug: "chosen-slug")

      expect(tenant.slug).to eq("chosen-slug")
    end

    it "appends a numeric suffix when the derived slug is already taken" do
      Tenant.create!(name: "Acme")
      second = Tenant.create!(name: "Acme")

      expect(second.slug).to eq("acme-2")
    end

    it "keeps incrementing the suffix past the first collision" do
      Tenant.create!(name: "Acme")
      Tenant.create!(name: "Acme")
      third = Tenant.create!(name: "Acme")

      expect(third.slug).to eq("acme-3")
    end
  end

  describe "slug validations" do
    it "requires a slug when none can be derived" do
      tenant = build(:tenant, slug: nil, name: nil)

      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to include("can't be blank")
    end

    it "rejects a duplicate slug" do
      create(:tenant, slug: "taken", name: "First")
      duplicate = build(:tenant, slug: "taken", name: "Second")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "rejects a slug with spaces or punctuation" do
      tenant = build(:tenant, slug: "Not A Slug!", name: "X")

      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug])
        .to include("must be lowercase letters, numbers, and single hyphens")
    end

    it "rejects an uppercase slug" do
      tenant = build(:tenant, slug: "UPPER", name: "X")

      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to be_present
    end

    it "accepts a well-formed slug" do
      tenant = build(:tenant, slug: "acme-corp-2", name: "Acme")

      expect(tenant).to be_valid
    end
  end
end
