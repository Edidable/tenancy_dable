# frozen_string_literal: true

# A tenant-scoped model with NO uniqueness validation (DESIGN.md §16.2/§16.7), so
# the create refusal is proven independent of whatever validators a model has.
class Gadget < ApplicationRecord
  include TenancyDable::Scoped

  belongs_to_tenant
end
