# frozen_string_literal: true

require "rails_helper"

# A representative concrete policy, showing how the secure-by-default base + the
# capability/same-tenant helpers compose into a real authorization table
# (DESIGN.md §9.3). This `WidgetPolicy` wires the conventional shape:
#
#   * reads  (index?/show?) require membership   — `member?`
#   * writes (create?/update?/destroy?) require management — `manager?`
#   * record-bearing actions additionally require the record to belong to the
#     acting tenant — `same_tenant?`
#
# so a manager of tenant A can create in A yet still cannot touch a row owned by
# tenant B (security invariant 2), and a non-member can do nothing.
RSpec.describe "A concrete WidgetPolicy < TenancyDable::Policy::Base" do
  let(:widget_policy_class) do
    Class.new(TenancyDable::Policy::Base) do
      def index? = member?

      def show? = member? && same_tenant?

      def create? = manager?

      def update? = manager? && same_tenant?

      def destroy? = manager? && same_tenant?
    end
  end

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }

  let(:own_widget) { create(:widget, tenant: tenant) }
  let(:foreign_widget) { create(:widget, tenant: other_tenant) }

  # Build the policy for a role acting in `acting_tenant` against `record`.
  def policy_for(role:, record:, acting_tenant: tenant)
    membership = role.nil? ? nil : build(:membership, role: role)
    context = TenancyDable.pundit_context(user: user, tenant: acting_tenant, membership: membership)
    widget_policy_class.new(context, record)
  end

  describe "a member acting on their own tenant's record" do
    subject(:policy) { policy_for(role: "member", record: own_widget) }

    it "may read (member)" do
      expect(policy.index?).to be(true)
      expect(policy.show?).to be(true)
    end

    it "may not write (not a manager)" do
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end
  end

  describe "a manager (admin) acting on their own tenant's record" do
    subject(:policy) { policy_for(role: "admin", record: own_widget) }

    it "may read (a manager is also a member)" do
      expect(policy.index?).to be(true)
      expect(policy.show?).to be(true)
    end

    it "may write (manager + same tenant)" do
      expect(policy.create?).to be(true)
      expect(policy.update?).to be(true)
      expect(policy.destroy?).to be(true)
    end
  end

  describe "an owner acting on their own tenant's record" do
    subject(:policy) { policy_for(role: "owner", record: own_widget) }

    it "may do everything (owner implies manager implies member)" do
      expect(policy.index?).to be(true)
      expect(policy.show?).to be(true)
      expect(policy.create?).to be(true)
      expect(policy.update?).to be(true)
      expect(policy.destroy?).to be(true)
    end
  end

  describe "a manager acting on ANOTHER tenant's record (cross-tenant)" do
    subject(:policy) { policy_for(role: "admin", record: foreign_widget) }

    it "may still read the collection and create (no record-tenant gate there)" do
      expect(policy.index?).to be(true)
      expect(policy.create?).to be(true)
    end

    it "may NOT touch the foreign record despite being a manager (same_tenant fails)" do
      expect(policy.show?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end
  end

  describe "a non-member (no membership in the acting tenant)" do
    subject(:policy) { policy_for(role: nil, record: own_widget) }

    it "may do nothing at all" do
      expect(policy.index?).to be(false)
      expect(policy.show?).to be(false)
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end
  end
end
