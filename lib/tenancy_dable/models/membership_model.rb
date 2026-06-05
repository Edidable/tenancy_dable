# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # Identity concern for the user<->tenant join model (default `Membership`). The
  # host mixes it in (`include TenancyDable::MembershipModel`); the railtie makes
  # the file available on `:active_record` load (DESIGN.md §2/§6.2).
  #
  # It carries the role, derives one boolean predicate per configured role, and
  # protects a workspace from ever losing its last owner.
  #
  # IMPORTANT: this concern deliberately does NOT `include TenancyDable::Scoped`.
  # Membership is queried to discover which tenants a user belongs to — `Resolvable`
  # and `User#membership_for` hit it BEFORE any tenant is current — so applying the
  # fail-closed tenant default scope here would deadlock resolution (DESIGN.md §5.3).
  # Phase 09 asserts Membership stays queryable with no `current_tenant`.
  module MembershipModel
    extend ActiveSupport::Concern

    included do
      belongs_to :user, class_name: TenancyDable.configuration.user_model
      belongs_to :tenant, class_name: TenancyDable.configuration.tenant_model

      # `in:` is a callable so the allowed set is read at validation time — a host
      # (or a spec) that reconfigures `roles` is honored without reloading the model.
      validates :role, inclusion: {in: ->(_record) { TenancyDable.configuration.roles }}
      validates :user_id, uniqueness: {scope: :tenant_id}

      # One predicate per configured role (`owner?`, `admin?`, `member?`, ...),
      # GENERATED from `config.roles` rather than hard-coded, so adding a role to
      # the config adds its predicate. Bound at include time (the conventional,
      # introspectable `respond_to?(:owner?)` surface); the host configures roles
      # in an initializer, before its models load.
      TenancyDable.configuration.roles.each do |role_name|
        define_method(:"#{role_name}?") { role == role_name }
      end

      # `owners` = the single highest role; `admins` = the manager set (owner +
      # admin by default). Both lambdas read config at call time.
      scope :owners, -> { where(role: TenancyDable.configuration.roles.first) }
      scope :admins, -> { where(role: TenancyDable.configuration.manager_roles) }

      before_update :prevent_last_owner_demotion
    end

    # Can this membership manage the workspace? True when its role is in
    # `config.manager_roles`.
    def manager?
      TenancyDable.configuration.manager_role?(role)
    end

    private

    # Last-owner guard (DESIGN.md §6.2): refuse to demote the ONLY owner of a
    # tenant, which would otherwise leave the workspace ownerless. Demoting one of
    # several owners is allowed. `throw :abort` halts the save (returns false /
    # `update!` raises) WITHOUT raising from the callback; the DB row is unchanged.
    def prevent_last_owner_demotion
      return unless will_save_change_to_role?

      owner_role = TenancyDable.configuration.roles.first
      previous_role, new_role = role_change_to_be_saved
      return unless previous_role == owner_role && new_role != owner_role

      other_owners = self.class
        .where(tenant_id: tenant_id, role: owner_role)
        .where.not(id: id)
      return if other_owners.exists?

      errors.add(:role, "cannot be changed: a tenant must keep at least one owner")
      throw :abort
    end
  end
end
