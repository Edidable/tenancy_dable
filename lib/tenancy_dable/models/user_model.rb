# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # Identity concern for the global identity model (default `User`). The host
  # mixes it in (`include TenancyDable::UserModel`); the railtie makes the file
  # available on `:active_record` load (DESIGN.md §2/§6.3).
  #
  # A user spans tenants: their memberships are the bridge resolution and
  # authorization walk to answer "which workspace, and as what role?". The
  # lookups below are the entry points `Resolvable` (Phase 05) uses, and they run
  # BEFORE any tenant is current — which is exactly why Membership is not
  # tenant-scoped (DESIGN.md §5.3).
  module UserModel
    extend ActiveSupport::Concern

    included do
      has_many :memberships,
        class_name: TenancyDable.configuration.membership_model,
        dependent: :destroy
      # Source association (`:tenant`) is inferred from the singularized name and
      # is stable even when the tenant model is renamed.
      has_many :tenants, through: :memberships
    end

    # This user's membership in `tenant`, or nil when `tenant` is nil or the user
    # is not a member. Looked up by foreign key so it does not depend on the
    # tenant being persisted-and-reloaded.
    def membership_for(tenant)
      return nil if tenant.nil?

      memberships.find_by(tenant_id: tenant.id)
    end

    # Whether this user is a member of `tenant` (nil tenant => false).
    def member_of?(tenant)
      membership_for(tenant).present?
    end
  end
end
