# frozen_string_literal: true

# Host model for the workspace. `TenancyDable::TenantModel` (Phase 04) adds the
# memberships/users associations, slug generation + presence/uniqueness/format
# validation, and #owners. NOT tenant-scoped — it IS the tenant.
class Tenant < ApplicationRecord
  include TenancyDable::TenantModel

  # Read through the tenant side (DESIGN.md §16.1): the shapes the read guard
  # refuses while acting in another tenant.
  has_many :widgets
  has_one :first_widget, -> { order(:id) }, class_name: "Widget"
  has_many :gadgets
end
