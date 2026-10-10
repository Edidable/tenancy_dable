# frozen_string_literal: true

module TenancyDable
  # The tenant context captured on one thread or fiber, to be restored on another
  # (DESIGN.md §16.4). RAW stored state (§4.2), not the readers: `membership` is
  # `Current.membership`, so the §15 rule still holds on the other side.
  #
  # `restore` routes the tenant through `TenancyDable.with_tenant`, so the
  # isolation check, the audit-override policy and the RLS hook all apply, and the
  # restoring thread's own tenant, membership and flag come back on exit or raise.
  # A snapshot taken inside `without_tenant` restores the flag with no reason check
  # and no event: the bypass was reported where it began.
  Snapshot = Data.define(:tenant, :membership, :tenant_scope_disabled) do
    def restore(&block)
      raise LocalJumpError, "no block given (yield)" unless block

      TenancyDable.with_tenant(tenant) do
        TenancyDable.current_membership = membership
        TenancyDable.__send__(:scope_disabled_as, tenant_scope_disabled, &block)
      end
    end
  end
end
