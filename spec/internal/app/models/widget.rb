# frozen_string_literal: true

# The scoping-engine system-under-test. Tenant-scoped via TenancyDable::Scoped
# (Phase 03). The self-referential `parent` (a tenant-scoped belongs_to back to
# Widget) is what exercises the cross-tenant belongs_to validation in Phase 08
# (DESIGN.md §5.1/§8); `validates_uniqueness_to_tenant :name` makes names unique
# per workspace rather than globally.
class Widget < ApplicationRecord
  include TenancyDable::Scoped

  belongs_to_tenant
  belongs_to :parent, class_name: "Widget", optional: true

  validates_uniqueness_to_tenant :name
end
