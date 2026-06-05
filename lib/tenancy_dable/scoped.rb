# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # The model-side scoping engine. A host model gains the `belongs_to_tenant`
  # macro by `include TenancyDable::Scoped`; the railtie makes the concern
  # available on `:active_record` load (DESIGN.md §2/§5.1).
  #
  # Everything contextual (the active tenant, the `without_tenant` bypass flag,
  # whether `require_tenant` is truthy) is read at QUERY time from
  # `TenancyDable::Current` / the configuration, so the same model behaves
  # correctly across requests, jobs, and the test suite. Everything structural
  # (the foreign-key column, the association) is captured ONCE when the model
  # declares itself scoped — exactly like a plain `belongs_to` bakes in its key.
  module Scoped
    extend ActiveSupport::Concern

    # Resolve `config.require_tenant` "truthy-in-context": a callable is invoked
    # and its result tested; a plain value is tested directly (DESIGN.md §5.1).
    # Lives here (not on the relation) so the fail-closed branch of the default
    # scope can reach it with a fully-qualified call.
    def self.require_tenant_in_context?
      value = TenancyDable.configuration.require_tenant
      result = value.respond_to?(:call) ? value.call : value
      !!result
    end

    class_methods do
      # Declare this model tenant-scoped on the `name` association (default
      # `:tenant`), keyed by `config.tenant_fk` (default `:tenant_id`).
      #
      # Installs, in order: the `belongs_to`, the `tenant_scoped?` class
      # predicate, the fail-closed default scope, create-time fk auto-assignment,
      # the post-create fk immutability guard, and the cross-tenant `belongs_to`
      # validation. See DESIGN.md §5.1 — the decision trees there are frozen.
      def belongs_to_tenant(name = :tenant, **opts)
        # Structural: bound once, at declaration time.
        fk = TenancyDable.configuration.tenant_fk

        belongs_to name, **opts

        # Present (=> true) ONLY on classes that called `belongs_to_tenant`, so
        # `respond_to?(:tenant_scoped?)` is the discriminator the bulk-write
        # guard and the cross-tenant validation rely on.
        define_singleton_method(:tenant_scoped?) { true }

        # Fail-closed default scope (invariant 1). Returning nil in the bypass /
        # fail-open branches lets ActiveRecord fall back to the unscoped relation
        # (`instance_exec(&scope) || default_scope`), so we never need `all`.
        default_scope do
          if TenancyDable::Current.tenant_scope_disabled
            # `without_tenant` bypass — fall through to the unscoped relation.
          elsif (active_tenant = TenancyDable.current_tenant)
            where(fk => active_tenant.id) # filter before any ordering (invariant 2)
          elsif TenancyDable::Scoped.require_tenant_in_context?
            raise TenancyDable::NoTenantError,
              "#{klass.name} was queried with no current tenant while require_tenant is active"
          end
          # No current tenant + require_tenant falsey → nil → unscoped (fail-open default).
        end

        # Auto-assign the fk from the current tenant on create when blank. Uses
        # `[]=` (write_attribute), bypassing the immutability writer below — and
        # the record is not yet persisted anyway, so the guard would not fire.
        before_validation(on: :create) do
          if self[fk].blank? && (active_tenant = TenancyDable.current_tenant)
            self[fk] = active_tenant.id
          end
        end

        # Immutability (invariant 3), assignment-time fail-fast on the fk writer
        # path (`record.tenant_id = x`, `update(tenant_id: x)`, mass-assign).
        # Allowed on a new record because it is not yet persisted.
        define_method(:"#{fk}=") do |value|
          current_value = read_attribute(fk)
          if persisted? && !current_value.nil? && value.to_s != current_value.to_s
            raise TenancyDable::TenantImmutableError,
              "#{self.class.name}##{fk} is immutable; a record's tenant cannot change after create"
          end
          self[fk] = value
        end

        # Immutability backstop at save-time, catching the association-writer
        # path (`record.tenant = other`) which sets the fk via write_attribute
        # and so slips past the writer override above.
        before_update do
          if will_save_change_to_attribute?(fk)
            raise TenancyDable::TenantImmutableError,
              "#{self.class.name}##{fk} is immutable; a record's tenant cannot change after create"
          end
        end

        # Cross-tenant `belongs_to` validation (invariant 2): every belongs_to
        # pointing at another tenant-scoped model must reference a record in the
        # SAME tenant. The target is read `unscoped` on purpose — the default
        # scope would otherwise hide a foreign-tenant row and mask the breach.
        validate do
          self_tenant_id = self[fk]
          next if self_tenant_id.nil?

          self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
            next if reflection.name == name # the tenant association itself
            next if reflection.options[:polymorphic]

            assoc_klass =
              begin
                reflection.klass
              rescue NameError
                next
              end
            next unless assoc_klass.respond_to?(:tenant_scoped?) && assoc_klass.tenant_scoped?

            assoc_id = self[reflection.foreign_key]
            next if assoc_id.nil?

            target_tenant_id = assoc_klass.unscoped.where(id: assoc_id).pick(fk)
            next if target_tenant_id.nil? || target_tenant_id == self_tenant_id

            errors.add(reflection.name, "belongs to a different tenant")
          end
        end
      end

      # Scope a uniqueness validation by the tenant fk (merging any caller-supplied
      # `:scope`), so e.g. names are unique WITHIN a workspace, not globally.
      def validates_uniqueness_to_tenant(*attr_names, **options)
        caller_scope = Array(options.delete(:scope))
        fk = TenancyDable.configuration.tenant_fk
        validates_uniqueness_of(*attr_names, scope: ([fk] + caller_scope).uniq, **options)
      end
    end
  end
end
