# frozen_string_literal: true

require "rails_helper"

# End-to-end cross-tenant isolation (PLAN security invariant 2; DESIGN §5.1).
# The full fixture graph — two tenants, two users, a membership each, and widgets
# in BOTH workspaces — is wired up, then read back THROUGH the scoping engine:
# acting in A, a Widget query returns only A's rows and never B's, and flipping
# the current tenant flips the entire visible set. This is the integration-level
# statement of what spec/scoping/default_scope_spec proves in isolation — with
# real records on both sides, the active tenant is the ONLY thing deciding what
# is visible.
RSpec.describe "Integration: cross-tenant isolation" do
  let(:tenant_a) { create(:tenant, slug: "alpha") }
  let(:tenant_b) { create(:tenant, slug: "bravo") }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  let!(:membership_a) { create(:membership, user: user_a, tenant: tenant_a, role: "owner") }
  let!(:membership_b) { create(:membership, user: user_b, tenant: tenant_b, role: "owner") }

  let!(:widget_a1) { create(:widget, tenant: tenant_a, name: "A-1") }
  let!(:widget_a2) { create(:widget, tenant: tenant_a, name: "A-2") }
  let!(:widget_b1) { create(:widget, tenant: tenant_b, name: "B-1") }

  it "wires two tenants, two users, and a membership scoping each user to one workspace" do
    expect(user_a.member_of?(tenant_a)).to be(true)
    expect(user_a.member_of?(tenant_b)).to be(false)
    expect(user_b.member_of?(tenant_b)).to be(true)
    expect(user_b.member_of?(tenant_a)).to be(false)
  end

  it "acting in A, a widget query never returns B's rows" do
    visible = TenancyDable.with_tenant(tenant_a) { Widget.all.to_a }

    expect(visible).to contain_exactly(widget_a1, widget_a2)
    expect(visible).not_to include(widget_b1)
    expect(visible.map(&:tenant_id).uniq).to eq([tenant_a.id])
  end

  it "flipping current_tenant flips the entire visible set" do
    in_a = TenancyDable.with_tenant(tenant_a) { Widget.pluck(:id) }
    in_b = TenancyDable.with_tenant(tenant_b) { Widget.pluck(:id) }

    expect(in_a).to contain_exactly(widget_a1.id, widget_a2.id)
    expect(in_b).to contain_exactly(widget_b1.id)
    expect(in_a & in_b).to be_empty # disjoint — no row is visible to both tenants
  end

  it "cannot load another tenant's row by id while acting in A" do
    # B's widget exists, but A's scope hides it: a keyed lookup raises rather than
    # crossing the boundary (the same RecordNotFound a non-existent id would give).
    expect {
      TenancyDable.with_tenant(tenant_a) { Widget.find(widget_b1.id) }
    }.to raise_error(ActiveRecord::RecordNotFound)

    # ...yet it is plainly reachable from its OWN tenant, proving the row is real
    # and the failure above was the scope, not a missing record.
    found = TenancyDable.with_tenant(tenant_b) { Widget.find(widget_b1.id) }
    expect(found).to eq(widget_b1)
  end

  describe "the current membership" do
    it "is nil inside another tenant, and returns once with_tenant exits" do
      TenancyDable.with_tenant(tenant_a) do
        TenancyDable.current_membership = membership_a

        TenancyDable.with_tenant(tenant_b) { expect(TenancyDable.current_membership).to be_nil }
        expect(TenancyDable.current_membership).to eq(membership_a)
      end
    end

    it "is nil after current_tenant is reassigned to another tenant" do
      TenancyDable.current_tenant = tenant_a
      TenancyDable.current_membership = membership_a
      TenancyDable.current_tenant = tenant_b

      expect(TenancyDable.current_membership).to be_nil
    end

    it "does not let a policy built inside another tenant use the outer role" do
      policy_class = Class.new(TenancyDable::Policy::Base) do
        def update? = manager? && same_tenant?
      end

      allowed = TenancyDable.with_tenant(tenant_a) do
        TenancyDable.current_membership = membership_a
        TenancyDable.with_tenant(tenant_b) do
          context = TenancyDable.pundit_context(
            user: user_a, tenant: TenancyDable.current_tenant, membership: TenancyDable.current_membership
          )
          policy_class.new(context, widget_b1).update?
        end
      end

      expect(allowed).to be(false)
    end
  end

  describe "foreign_membership?" do
    it "is false with no membership, false in its own tenant, and true inside another" do
      TenancyDable.with_tenant(tenant_a) do
        expect(TenancyDable.foreign_membership?).to be(false)
        TenancyDable.current_membership = membership_a
        expect(TenancyDable.foreign_membership?).to be(false)

        TenancyDable.with_tenant(tenant_b) { expect(TenancyDable.foreign_membership?).to be(true) }
      end
    end

    it "is true with no current tenant, as in a job whose tenant was deleted" do
      TenancyDable.with_tenant(nil) do
        TenancyDable.current_membership = membership_a

        expect(TenancyDable.current_membership).to be_nil
        expect(TenancyDable.foreign_membership?).to be(true)
      end
    end
  end
end
