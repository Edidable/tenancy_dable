# frozen_string_literal: true

require "rails_helper"

# The capability predicates a concrete policy composes its actions from
# (DESIGN.md §9.3). All three are pure functions of the acting `role`, derived
# from config so they track the host's configured role names rather than
# hard-coding owner/admin/member:
#
#   * `owner?`   -> role is the highest (first) configured role;
#   * `manager?` -> role is in `config.manager_roles` (the "can manage" set);
#   * `member?`  -> any role is present.
#
# A nil role (no membership) must fail every predicate — closed by default.
#
# These helpers are PRIVATE on `Base` (DESIGN.md §10-D); a thin subclass
# re-publicizes them UNDER THEIR REAL NAMES so the matrix can be asserted in
# isolation, exactly as a concrete policy would call them.
RSpec.describe "TenancyDable::Policy::Base capability predicates" do
  let(:probe_class) do
    Class.new(TenancyDable::Policy::Base) { public :owner?, :manager?, :member? }
  end

  # Role drives every predicate; tenant/record are irrelevant here, so a nil
  # record keeps each case focused on the role alone.
  def probe_for(role)
    membership = role.nil? ? nil : build(:membership, role: role)
    context = TenancyDable.pundit_context(
      user: build(:user),
      tenant: build(:tenant),
      membership: membership
    )
    probe_class.new(context, nil)
  end

  # role     => [owner?, manager?, member?]   (default config)
  {
    "owner" => [true, true, true],
    "admin" => [false, true, true],
    "member" => [false, false, true],
    nil => [false, false, false] # no membership / no tenant in context
  }.each do |role, (is_owner, is_manager, is_member)|
    context "for the #{role.inspect} role" do
      let(:probe) { probe_for(role) }

      it "owner? is #{is_owner}" do
        expect(probe.owner?).to be(is_owner)
      end

      it "manager? is #{is_manager}" do
        expect(probe.manager?).to be(is_manager)
      end

      it "member? is #{is_member}" do
        expect(probe.member?).to be(is_member)
      end
    end
  end

  it "derives the matrix from config rather than hard-coding owner/admin/member" do
    # Reconfigure to a role set sharing none of its non-owner names with the
    # default. `editor` can only register as a manager, and `viewer` as a plain
    # member, if the predicates read config at call time.
    TenancyDable.configure do |c|
      c.roles = %w[owner editor viewer]
      c.manager_roles = %w[owner editor]
    end

    expect(probe_for("owner").owner?).to be(true)
    expect(probe_for("editor").owner?).to be(false)
    expect(probe_for("editor").manager?).to be(true)
    expect(probe_for("viewer").manager?).to be(false)
    expect(probe_for("viewer").member?).to be(true)
  end
end
