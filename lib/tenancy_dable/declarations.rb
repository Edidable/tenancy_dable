# frozen_string_literal: true

module TenancyDable
  # One model's tenancy decision (frozen value object, DESIGN.md §16.3).
  #   kind            :scoped | :global
  #   reason          String for :global, nil for :scoped
  #   tag             Symbol | String | nil  (free-form; a host builds its own grouping on it)
  #   allow_tenant_fk true | false           (always false for :scoped)
  Declaration = Data.define(:kind, :reason, :tag, :allow_tenant_fk)

  # Extended onto `ActiveRecord::Base` by the railtie, so every Active Record
  # class has the macro and the readers (§16.3). `Scoped` stays a separate,
  # explicit include.
  #
  # INERT STUB (foundation): final signatures, no behaviour. W2 fills in
  # `tenancy_declare!` and the readers (§16.3).
  module Declarations
    # Declare this model global by decision, with the reason on record.
    def tenant_global(because:, tag: nil, allow_tenant_fk: false)
      tenancy_declare!(:global, reason: because, tag: tag, allow_tenant_fk: allow_tenant_fk)
    end

    # The class's own declaration, else its superclass's (§16.3).
    def tenancy_declaration
      nil
    end

    def tenancy_global_reason
      tenancy_declaration&.reason
    end

    def tenancy_tag
      tenancy_declaration&.tag
    end

    private

    # The single writer; `tenant_global` and `belongs_to_tenant` both call it.
    def tenancy_declare!(kind, reason: nil, tag: nil, allow_tenant_fk: false)
      nil
    end
  end
end
