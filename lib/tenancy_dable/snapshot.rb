# frozen_string_literal: true

module TenancyDable
  # The tenant context captured on one thread or fiber, to be restored on another
  # (DESIGN.md §16.4). RAW stored state (§4.2), not the readers: `membership` is
  # `Current.membership`, so the §15 rule still holds on the other side.
  #
  # INERT STUB (foundation): final members; `restore` just yields. W4 fills in
  # `restore` (§16.4).
  Snapshot = Data.define(:tenant, :membership, :tenant_scope_disabled) do
    def restore(&block)
      raise LocalJumpError, "no block given (yield)" unless block

      yield
    end
  end
end
