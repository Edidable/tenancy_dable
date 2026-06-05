# frozen_string_literal: true

require "rails_helper"

# Secure-by-default core (DESIGN.md §9.3, PLAN "Authorization"). The whole point
# of `Policy::Base` is that forgetting to define an action DENIES rather than
# leaks: every action returns `false` until a subclass explicitly grants it. We
# assert this on a BARE subclass (no overrides) — the shape every concrete policy
# starts from — built even with a fully-privileged owner context, so the denial
# is provably the default and not a side effect of a weak subject.
#
# Also pinned here: the `new? -> create?` / `edit? -> update?` delegation
# (DESIGN.md §10-B) — granting a write grants its form, with the deny still the
# default until the write is granted.
RSpec.describe "TenancyDable::Policy::Base secure-by-default" do
  # An owner of the record's own tenant: the most privileged subject possible.
  # If even THIS is denied by a bare policy, the default is genuinely closed.
  let(:tenant) { create(:tenant) }
  let(:record) { create(:widget, tenant: tenant) }
  let(:context) do
    TenancyDable.pundit_context(
      user: create(:user),
      tenant: tenant,
      membership: build(:membership, role: "owner")
    )
  end

  let(:bare_policy_class) { Class.new(TenancyDable::Policy::Base) }

  %i[index? show? create? new? update? edit? destroy?].each do |action|
    it "denies ##{action} on a bare subclass even for an owner of the record's tenant" do
      policy = bare_policy_class.new(context, record)

      expect(policy.public_send(action)).to be(false)
    end
  end

  it "denies every action on Policy::Base itself" do
    policy = TenancyDable::Policy::Base.new(context, record)

    %i[index? show? create? new? update? edit? destroy?].each do |action|
      expect(policy.public_send(action)).to be(false)
    end
  end

  describe "new? / edit? delegate to their write action" do
    it "new? follows create? once a subclass grants create?" do
      granting_create = Class.new(TenancyDable::Policy::Base) do
        def create?
          true
        end
      end
      policy = granting_create.new(context, record)

      expect(policy.create?).to be(true)
      expect(policy.new?).to be(true)
    end

    it "edit? follows update? once a subclass grants update?" do
      granting_update = Class.new(TenancyDable::Policy::Base) do
        def update?
          true
        end
      end
      policy = granting_update.new(context, record)

      expect(policy.update?).to be(true)
      expect(policy.edit?).to be(true)
    end

    it "keeps new?/edit? closed while their write action stays denied" do
      policy = bare_policy_class.new(context, record)

      expect(policy.new?).to be(false)
      expect(policy.edit?).to be(false)
    end
  end
end
