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
  module Declarations
    # Declare this model global by decision, with the reason on record.
    def tenant_global(because:, tag: nil, allow_tenant_fk: false)
      tenancy_declare!(:global, reason: because, tag: tag, allow_tenant_fk: allow_tenant_fk)
    end

    # The class's own declaration, else its superclass's (§16.3).
    def tenancy_declaration
      @tenancy_declaration || (superclass.tenancy_declaration if superclass.respond_to?(:tenancy_declaration))
    end

    def tenancy_global_reason
      tenancy_declaration&.reason
    end

    def tenancy_tag
      tenancy_declaration&.tag
    end

    private

    # The single writer; `tenant_global` and `belongs_to_tenant` both call it.
    # Every check runs before anything is stored (§16.3), in the frozen order.
    def tenancy_declare!(kind, reason: nil, tag: nil, allow_tenant_fk: false)
      label = name || "an anonymous model"

      if kind == :global && !(reason.is_a?(String) && reason.match?(/\S/))
        raise ConfigurationError, "#{label}: tenant_global requires a non-blank because: reason"
      end
      unless tag.nil? || tag.is_a?(Symbol) || tag.is_a?(String)
        raise ConfigurationError, "#{label}: tag must be a Symbol or String"
      end
      unless [true, false].include?(allow_tenant_fk)
        raise ConfigurationError, "#{label}: allow_tenant_fk must be true or false"
      end
      if (existing = tenancy_declaration)
        raise ConfigurationError,
          "#{label} already declared its tenancy (#{existing.kind}); a declaration cannot be changed"
      end

      @tenancy_declaration = Declaration.new(
        kind: kind, reason: reason&.dup&.freeze, tag: tag, allow_tenant_fk: allow_tenant_fk
      )
    end
  end
end
