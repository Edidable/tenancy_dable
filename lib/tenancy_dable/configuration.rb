# frozen_string_literal: true

require "active_support/core_ext/string/inflections" # String#constantize
require "tenancy_dable/errors"

module TenancyDable
  # Configuration DSL for the host application, set via
  # `TenancyDable.configure { |c| ... }`.
  #
  # Every setting and default below is FROZEN by the contract (DESIGN.md §4.1 /
  # PLAN.md). The resolver helpers (`tenant_class`, `role?`, ...) are internal
  # conveniences implied by "model names" + "predicates generated from this"
  # (§10-E); they are not new public guarantees, but the settings and their
  # defaults are.
  class Configuration
    # Model names (resolved to constants lazily, so the host's models need not be
    # loaded when the gem is configured).
    attr_accessor :tenant_model, :user_model, :membership_model

    # Roles, ordered highest-first; predicates and the manager set derive from
    # these (see MembershipModel / Policy::Base in later phases).
    attr_accessor :roles, :manager_roles

    # Column / param names.
    attr_accessor :tenant_fk, :slug_param

    # Behaviour switches.
    attr_accessor :require_tenant, :rls, :rls_statement, :audit_overrides,
      :on_tenant_not_found, :on_not_a_member, :current_user_resolver

    def initialize
      @tenant_model = "Tenant"
      @user_model = "User"
      @membership_model = "Membership"
      @roles = %w[owner admin member]
      @manager_roles = %w[owner admin]
      @tenant_fk = :tenant_id
      @slug_param = :tenant_slug
      @require_tenant = false
      @rls = false
      @rls_statement = ->(tenant) { "SET app.tenant_id = #{ActiveRecord::Base.connection.quote(tenant&.id)}" }
      @audit_overrides = :log
      @on_tenant_not_found = :raise
      # Behavior when the acting user is NOT a member of the resolved tenant
      # (v0.2.0, additive). The default preserves today's behavior — raise
      # `NotAMemberError`. `:not_authorized` raises `Pundit::NotAuthorizedError`
      # instead; a callable `->(tenant)` runs in the controller for full host
      # control. Validated in `validate!`; dispatched by Resolvable (§9.1 step 3).
      @on_not_a_member = :not_a_member_error
      # Auth-agnostic: read the host app's `Current.user` (the conventional
      # Rails CurrentAttributes pattern) when present, else nil. `::Current` is
      # explicit so this resolves the HOST's top-level model, never
      # `TenancyDable::Current` (which has no `user`).
      @current_user_resolver = -> { (defined?(::Current) && ::Current.respond_to?(:user)) ? ::Current.user : nil }
    end

    # --- resolver helpers (internal conveniences) --------------------------

    def tenant_class
      tenant_model.to_s.constantize
    end

    def user_class
      user_model.to_s.constantize
    end

    def membership_class
      membership_model.to_s.constantize
    end

    def role?(name)
      Array(roles).include?(name.to_s)
    end

    def manager_role?(name)
      Array(manager_roles).include?(name.to_s)
    end

    # --- validation --------------------------------------------------------

    # Raises ConfigurationError on the misconfigurations the contract names
    # (§4.1): empty roles, manager_roles not a subset of roles, a blank model
    # name, or an `on_not_a_member` symbol outside the known set. Called by
    # `TenancyDable.configure` after the host's block runs.
    def validate!
      raise ConfigurationError, "roles must not be empty" if Array(roles).empty?

      stray = Array(manager_roles) - Array(roles)
      unless stray.empty?
        raise ConfigurationError, "manager_roles #{stray.inspect} must be a subset of roles"
      end

      {tenant_model: tenant_model, user_model: user_model, membership_model: membership_model}.each do |setting, value|
        if value.nil? || value.to_s.strip.empty?
          raise ConfigurationError, "#{setting} must not be blank"
        end
      end

      # A Symbol must name a known mode; a callable (host-supplied handler) is
      # accepted as-is — it runs in the controller at the call site (Resolvable).
      if on_not_a_member.is_a?(Symbol) && !%i[not_a_member_error not_authorized].include?(on_not_a_member)
        raise ConfigurationError,
          "on_not_a_member #{on_not_a_member.inspect} must be :not_a_member_error, :not_authorized, or a callable"
      end

      self
    end
  end
end
