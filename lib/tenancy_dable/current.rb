# frozen_string_literal: true

require "active_support/current_attributes"
require "active_support/code_generator" # CurrentAttributes.attribute uses this; not auto-required in lib-only mode

module TenancyDable
  # Per-request / per-thread tenancy context, backed by
  # ActiveSupport::CurrentAttributes (automatically reset between Rails requests
  # and between RSpec examples — see spec/rails_helper.rb).
  #
  # This holds ONLY raw state. All behaviour — the audit-override check, the RLS
  # hook, and `with_tenant` / `without_tenant` — lives on the `TenancyDable`
  # facade (DESIGN.md §3/§4.2), so there is a single, auditable mutation path for
  # the current tenant rather than logic scattered across attribute writers.
  #
  #   * tenant                 — the active workspace record (or nil)
  #   * membership             - the acting user's membership as set, possibly
  #                              another tenant's (`TenancyDable.current_membership`
  #                              answers it only inside its own tenant)
  #   * tenant_scope_disabled  — flag toggled by `without_tenant`; the scoping
  #                              engine (Phase 03) and bulk-write guard read it
  #                              to bypass tenant filtering.
  class Current < ActiveSupport::CurrentAttributes
    attribute :tenant, :membership, :tenant_scope_disabled
  end
end
