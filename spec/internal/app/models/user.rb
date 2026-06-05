# frozen_string_literal: true

# Host model for the global identity. `TenancyDable::UserModel` (Phase 04) adds
# the memberships/tenants associations, #membership_for, and #member_of?.
class User < ApplicationRecord
  include TenancyDable::UserModel
end
