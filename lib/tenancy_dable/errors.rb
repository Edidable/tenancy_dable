# frozen_string_literal: true

module TenancyDable
  # Base for every error this gem raises. Hosts can `rescue TenancyDable::Error`
  # to trap any tenancy failure with a single clause.
  #
  # This file has NO dependencies and is loaded first (see DESIGN.md §2) so every
  # other unit may reference these classes. The frozen set below is the contract
  # (DESIGN.md §7) — names are stable; downstream phases raise them by name.
  class Error < StandardError; end

  # Fail-closed (invariant 1): a scoped query ran with no current tenant while
  # `config.require_tenant` was truthy-in-context. Raised by the default scope
  # (Phase 03) instead of silently returning every tenant's rows.
  class NoTenantError < Error; end

  # Invariant 3: something tried to reassign the tenant foreign key of an
  # already-persisted record. The tenant of a row is immutable after create.
  class TenantImmutableError < Error; end

  # A guarded bulk write (`update_all` / `delete_all` / `destroy_all`) ran on a
  # tenant-scoped relation with no active tenant, or on a relation that is not
  # provably scoped to the current tenant (Phase 03, §5.2).
  class BulkWriteError < Error; end

  # A tenant-scoped `belongs_to` pointed at a record from a different tenant.
  # Used as the cross-tenant validation message style (Phase 03, §5.1). The
  # `MESSAGE` constant is the single source of truth for that validation string;
  # `Scoped` adds it to the record's errors (validation adds — it does not raise).
  class CrossTenantError < Error
    MESSAGE = "belongs to a different tenant"
  end

  # Resolution found an acting user who is not a member of the resolved tenant
  # (Phase 05, §9). Membership is required to enter a workspace.
  class NotAMemberError < Error; end

  # Reserved for host / non-bang `find_by` resolution strategies (DESIGN.md
  # §10-A). Note: the `Resolvable` `:raise` path itself raises
  # `ActiveRecord::RecordNotFound` (via `find_by!`); this symbol coexists with it.
  class TenantNotFoundError < Error; end

  # `current_tenant=` was reassigned to a DIFFERENT tenant while
  # `config.audit_overrides == :raise` (§4.2). Guards against accidental
  # mid-request tenant switches.
  class TenantOverrideError < Error; end

  # Invalid configuration — empty `roles`, `manager_roles` not a subset of
  # `roles`, or a blank model name (§4.1). Raised by `Configuration#validate!`.
  class ConfigurationError < Error; end
end
