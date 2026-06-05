# frozen_string_literal: true

require "tenancy_dable/version"
require "tenancy_dable/errors"
require "tenancy_dable/configuration"
require "tenancy_dable/current"
require "tenancy_dable/policy/context"
require "tenancy_dable/policy/base"
require "tenancy_dable/railtie"

# TenancyDable — opinionated multi-workspace tenancy for Rails SaaS apps.
#
# The standards-propagation tenancy layer extracted from the edidable Rails SaaS
# skeleton. Host apps depend on this one gem and inherit, versioned:
#
#   * Row-scoping engine — fail-closed by default, immutable tenant_id,
#     bulk-write guard, ActiveJob tenant propagation, optional Postgres RLS hook.
#   * Multi-workspace identity — User <-> Membership <-> Tenant, roles
#     (owner/admin/member), last-owner guard.
#   * Slug resolution — "/:tenant_slug" -> tenant + membership enforcement.
#   * Authorization — a Pundit Context (user + tenant + membership) + base policy.
#
# This module is the public facade: configuration plus the current-tenant
# context. The scoping engine, identity concerns, resolution, and authorization
# layers are mixed in by the railtie as later phases land (see .midgal/PLAN.md).
module TenancyDable
  class << self
    # --- configuration -----------------------------------------------------

    # Yields the memoized Configuration, validates it, and returns it.
    #
    #   TenancyDable.configure do |config|
    #     config.tenant_model   = "Workspace"
    #     config.require_tenant = true
    #   end
    def configure
      if block_given?
        yield(configuration)
        configuration.validate!
      end
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Test/boot reset hook (additive, DESIGN.md §10-F).
    def reset_configuration!
      @configuration = Configuration.new
    end

    # --- current context (delegates to Current; §4) ------------------------

    def current_tenant
      Current.tenant
    end

    # The ONLY place the audit-override policy and the RLS hook fire (§3/§4.2).
    # Assigning the same tenant, or setting from/to nil, is a normal
    # establish/clear and is never treated as an override.
    def current_tenant=(tenant)
      previous = Current.tenant
      audit_override(previous, tenant)
      Current.tenant = tenant
      fire_rls(previous, tenant)
    end

    def current_membership
      Current.membership
    end

    def current_membership=(membership)
      Current.membership = membership
    end

    # Run a block with `tenant` as the current tenant, restoring the prior
    # tenant + membership afterwards (nesting-safe). Routes through
    # `current_tenant=` so the RLS hook tracks the change on entry AND on
    # restore — otherwise an enabled RLS session variable would stay pointed at
    # the inner tenant after the block (a cross-tenant leak). Returns the block's
    # value.
    def with_tenant(tenant)
      previous_tenant = Current.tenant
      previous_membership = Current.membership
      self.current_tenant = tenant
      yield
    ensure
      self.current_tenant = previous_tenant
      self.current_membership = previous_membership
    end

    # Run a block with tenant scoping disabled (scoped models return `all`),
    # restoring the prior flag afterwards (nesting-safe). Returns the block's
    # value. Does not touch the tenant itself, so no audit/RLS hook fires.
    def without_tenant
      previous = Current.tenant_scope_disabled
      Current.tenant_scope_disabled = true
      yield
    ensure
      Current.tenant_scope_disabled = previous
    end

    # --- authorization builder (additive, introduced Phase 06; §6) ---------

    # Build the Pundit subject: the acting user PLUS the workspace and membership
    # they are acting under (DESIGN.md §3/§9.2). Policies and `policy_scope`
    # decide on this `Policy::Context` triple rather than a bare user, since the
    # same user holds a different role — or none — in each tenant. Host
    # controllers pass the result wherever Pundit expects its "user".
    def pundit_context(user:, tenant:, membership:)
      Policy::Context.new(user: user, tenant: tenant, membership: membership)
    end

    private

    # Audit policy for a `current_tenant=` reassignment (§4.2). Only a switch
    # between two DIFFERENT, non-nil tenants counts as an override; setting from
    # nil, to nil, or to the same tenant is a normal establish/clear.
    def audit_override(previous, new_tenant)
      return if previous.nil? || new_tenant.nil?
      return if previous.id == new_tenant.id

      behavior = configuration.audit_overrides
      return if behavior == :ignore

      if behavior == :raise
        raise TenantOverrideError, "current_tenant reassigned from tenant ##{previous.id} to tenant ##{new_tenant.id}"
      end

      # Default (:log). Invariant 6: log tenant ids only, never record payloads.
      logger&.warn("[TenancyDable] current_tenant override: tenant ##{previous.id} -> tenant ##{new_tenant.id}")
    end

    # RLS hook (§4.2): when enabled and the effective tenant id actually changes,
    # emit `rls_statement` against the AR connection.
    def fire_rls(previous, new_tenant)
      return unless configuration.rls
      return if previous&.id == new_tenant&.id

      statement = configuration.rls_statement.call(new_tenant)
      ActiveRecord::Base.connection.execute(statement) if statement
    end

    def logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      return ActiveRecord::Base.logger if defined?(ActiveRecord::Base) && ActiveRecord::Base.logger

      nil
    end
  end
end
