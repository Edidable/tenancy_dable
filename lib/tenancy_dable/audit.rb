# frozen_string_literal: true

module TenancyDable
  # Declaration audit (DESIGN.md §16.3): proves every model either scopes itself
  # or says why it is global.
  #
  # INERT STUB (foundation): final constants and value object; `run` finds
  # nothing. W2 fills in `run` (§16.3).
  module Audit
    KINDS = %i[undeclared global_with_tenant_fk scoped_without_index].freeze

    # `model` is the class; `kind` is one of KINDS.
    Finding = Data.define(:model, :kind, :message) do
      def to_s = "#{model.name}: #{message}"
    end

    def self.run(models = nil)
      [].freeze
    end
  end
end
