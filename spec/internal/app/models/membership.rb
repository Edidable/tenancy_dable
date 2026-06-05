# frozen_string_literal: true

# Host model for the user<->tenant join. `TenancyDable::MembershipModel`
# (Phase 04) adds the user/tenant belongs_to, role inclusion + generated
# predicates, owners/admins scopes, the last-owner-demotion guard, and #manager?.
#
# NOTE: Membership is deliberately NOT tenant-scoped — it is queried to discover
# a user's tenants *before* any tenant is current, so scoping it would deadlock
# resolution (DESIGN.md §5.3). It must never `include TenancyDable::Scoped`.
class Membership < ApplicationRecord
  include TenancyDable::MembershipModel
end
