# frozen_string_literal: true

# Host model for the workspace. `TenancyDable::TenantModel` (Phase 04) adds the
# memberships/users associations, slug generation + presence/uniqueness/format
# validation, and #owners. NOT tenant-scoped — it IS the tenant.
class Tenant < ApplicationRecord
  include TenancyDable::TenantModel
end
