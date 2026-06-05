# frozen_string_literal: true

require "rails_helper"

# Role-derived booleans on MembershipModel (DESIGN.md §6.2). Two surfaces:
#
#   * one predicate per configured role (`owner?`/`admin?`/`member?`), GENERATED
#     from `config.roles` at include time rather than hard-coded, so adding a role
#     to the config adds its predicate;
#   * `#manager?`, true when the role is in `config.manager_roles`.
#
# Predicates are read off the role string, so an unsaved `build(:membership)` is
# enough — no database round-trip is needed to exercise them.
RSpec.describe "TenancyDable::MembershipModel — role predicates" do
  describe "generated role predicates" do
    it "owner? is true only for the owner role" do
      expect(build(:membership, role: "owner").owner?).to be(true)
      expect(build(:membership, role: "admin").owner?).to be(false)
      expect(build(:membership, role: "member").owner?).to be(false)
    end

    it "admin? is true only for the admin role" do
      expect(build(:membership, role: "admin").admin?).to be(true)
      expect(build(:membership, role: "owner").admin?).to be(false)
      expect(build(:membership, role: "member").admin?).to be(false)
    end

    it "member? is true only for the member role" do
      expect(build(:membership, role: "member").member?).to be(true)
      expect(build(:membership, role: "owner").member?).to be(false)
      expect(build(:membership, role: "admin").member?).to be(false)
    end

    it "defines a predicate for every configured role" do
      membership = build(:membership, role: "member")

      TenancyDable.configuration.roles.each do |role_name|
        expect(membership).to respond_to(:"#{role_name}?")
      end
    end

    it "derives the predicate set from config.roles rather than hard-coding owner/admin/member" do
      # Reconfigure to a role set that shares NONE of its non-owner names with the
      # default, then include the concern into a fresh model. A predicate named
      # `editor?` can only exist if the set is generated from config — proving the
      # generation is config-driven, not a baked-in owner/admin/member list.
      # (manager_roles must stay a subset of roles or `configure` raises.)
      TenancyDable.configure do |c|
        c.roles = %w[owner editor viewer]
        c.manager_roles = %w[owner editor]
      end

      membership_class = Class.new(ActiveRecord::Base) do
        self.table_name = "memberships"
        include TenancyDable::MembershipModel
      end

      editor = membership_class.new(role: "editor")

      expect(editor).to respond_to(:editor?)
      expect(editor).to respond_to(:viewer?)
      expect(editor.editor?).to be(true)
      expect(editor.viewer?).to be(false)
      expect(editor.owner?).to be(false)
    end
  end

  describe "#manager?" do
    it "is true for owner and admin (the default manager roles)" do
      expect(build(:membership, role: "owner").manager?).to be(true)
      expect(build(:membership, role: "admin").manager?).to be(true)
    end

    it "is false for member" do
      expect(build(:membership, role: "member").manager?).to be(false)
    end

    it "tracks a reconfigured manager_roles set" do
      # `manager?` reads config at call time, so narrowing manager_roles to just
      # owner immediately demotes admin from manager status.
      TenancyDable.configure { |c| c.manager_roles = %w[owner] }

      expect(build(:membership, role: "owner").manager?).to be(true)
      expect(build(:membership, role: "admin").manager?).to be(false)
    end
  end
end
