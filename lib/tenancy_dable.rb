# frozen_string_literal: true

require "active_support/notifications"
require "tenancy_dable/version"
require "tenancy_dable/errors"
require "tenancy_dable/configuration"
require "tenancy_dable/current"
require "tenancy_dable/snapshot"
require "tenancy_dable/audit"
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
  # Instrumented by `without_tenant` (§16.5).
  WITHOUT_TENANT_EVENT = "without_tenant.tenancy_dable"

  # The directory `call_site` skips (§16.5): frames inside the gem are not the
  # caller of `without_tenant`.
  LIB_DIR = "#{File.expand_path(__dir__)}/"
  private_constant :LIB_DIR

  UNSAFE_ISOLATION_MESSAGE = "tenant state written under a fiber scheduler with thread isolation; " \
    "set config.active_support.isolation_level = :fiber"
  private_constant :UNSAFE_ISOLATION_MESSAGE

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
      check_isolation!
      previous = Current.tenant
      audit_override(previous, tenant)
      Current.tenant = tenant
      fire_rls(previous, tenant)
    end

    # The acting membership, but only while it belongs to the current tenant, so
    # inside `with_tenant(other)` nothing decides with a role from another tenant.
    def current_membership
      membership = Current.membership
      tenant = Current.tenant
      membership if tenant && membership&.tenant_id == tenant.id
    end

    # A membership is set but it is not the current tenant's, or no tenant is
    # current. A host that treats a nil `current_membership` as a system context
    # must check this too.
    def foreign_membership?
      !Current.membership.nil? && current_membership.nil?
    end

    def current_membership=(membership)
      check_isolation!
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
    #
    # Order (§16.5): the reason check, the isolation check, the event, then the
    # flag. The event carries the host's reason, the tenant id and the call site,
    # never a record (invariant 6).
    def without_tenant(reason: nil)
      unless reason.nil? || reason.is_a?(String) || reason.is_a?(Symbol)
        raise BypassReasonError,
          "without_tenant reason: must be a String or a Symbol, got #{reason.class}"
      end

      if configuration.require_bypass_reason && (reason.nil? || reason.to_s.strip.empty?)
        raise BypassReasonError,
          "without_tenant requires a non-blank reason: (config.require_bypass_reason is on)"
      end

      check_isolation!
      notifier = ActiveSupport::Notifications.notifier
      if notifier.listening?(WITHOUT_TENANT_EVENT)
        # No block on purpose: with one, a raising block would add its exception
        # (which can carry a record) to the payload.
        ActiveSupport::Notifications.instrument(
          WITHOUT_TENANT_EVENT,
          reason: reason,
          tenant_id: Current.tenant&.id,
          call_site: call_site
        )
      end

      scope_disabled_as(true, check: false) { yield }
    end

    # --- context carrier and audit (v0.5.0; §16.3/§16.4) -------------------

    # The raw tenant state of this thread or fiber, to restore on another.
    def snapshot
      Snapshot.new(
        tenant: Current.tenant,
        membership: Current.membership,
        tenant_scope_disabled: Current.tenant_scope_disabled
      )
    end

    # A lambda running the block inside the snapshot taken NOW:
    # `Thread.new(&TenancyDable.carry { work })`.
    def carry(&block)
      raise LocalJumpError, "no block given (yield)" unless block

      captured = snapshot
      ->(*args, **kwargs) { captured.restore { block.call(*args, **kwargs) } }
    end

    # Findings for models whose tenancy is undeclared or suspicious (§16.3).
    def audit(models = nil)
      Audit.run(models)
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

    # Sets the bypass flag for the block and restores the prior one in `ensure`.
    # The only writer of `tenant_scope_disabled` (§16.4); `without_tenant` has
    # already run the isolation check before its event, so it passes `check: false`.
    def scope_disabled_as(value, check: true)
      check_isolation! if check
      previous = Current.tenant_scope_disabled
      begin
        Current.tenant_scope_disabled = value
        yield
      ensure
        Current.tenant_scope_disabled = previous
      end
    end

    # Isolation check (§16.4): runs first in every gem write to `Current`. Under a
    # fiber scheduler with thread isolation every fiber on the thread shares one
    # `Current`, a live cross-request leak.
    def check_isolation!
      mode = configuration.isolation_check
      return if mode == :off
      return unless Fiber.scheduler
      return unless ActiveSupport::IsolatedExecutionState.isolation_level == :thread

      raise UnsafeIsolationError, UNSAFE_ISOLATION_MESSAGE unless mode == :warn

      logger&.warn("[TenancyDable] #{UNSAFE_ISOLATION_MESSAGE}")
    end

    # `"path:lineno"` of the first caller outside the gem, or nil (§16.5).
    def call_site
      location = caller_locations(1).find { |loc| !(loc.absolute_path || loc.path).to_s.start_with?(LIB_DIR) }
      location && "#{location.absolute_path || location.path}:#{location.lineno}"
    end

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
