# frozen_string_literal: true

require "tenancy_dable/version"
require "tenancy_dable/configuration"

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
# The concrete layers are added by the Midgal build plan (see .midgal/PLAN.md);
# this entry point only wires configuration so the gem loads green from day one.
module TenancyDable
  class Error < StandardError; end

  class << self
    # TenancyDable.configure do |config|
    #   config.tenant_model     = "Tenant"
    #   config.user_model       = "User"
    #   config.membership_model = "Membership"
    #   config.require_tenant   = ->(*) { ActiveSupport::CurrentAttributes ... }
    # end
    def configure
      yield(configuration) if block_given?
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Test/boot reset hook.
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
