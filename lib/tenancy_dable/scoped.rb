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
      # Installs, in order: the tenancy declaration (§16.3), the `belongs_to`, the `tenant_scoped?` class
      # predicate, the fail-closed default scope, create-time fk auto-assignment,
      # the post-create fk immutability guard, and the cross-tenant `belongs_to`
      # validation. See DESIGN.md §5.1 — the decision trees there are frozen.
      def belongs_to_tenant(name = :tenant, tag: nil, **opts)
        tenancy_declare!(:scoped, tag: tag) # a re-declaration raises before anything is installed

        # Structural: bound once, at declaration time.
        fk = TenancyDable.configuration.tenant_fk

        belongs_to name, **opts

        # Present (=> true) ONLY on classes that called `belongs_to_tenant`, so
        # `respond_to?(:tenant_scoped?)` is the discriminator the bulk-write
        # guard and the cross-tenant validation rely on.
        define_singleton_method(:tenant_scoped?) { true }

        # Fail-closed default scope (invariant 1). The bypass / fail-open branches
        # return the relation marked as built without a tenant (§16.1), so loading
        # it later inside a tenant is refused rather than reading every tenant.
        default_scope do
          if TenancyDable::Current.tenant_scope_disabled
            extending(TenancyDable::BuiltWithoutTenant) # `without_tenant` bypass
          elsif (active_tenant = TenancyDable.current_tenant)
            where(fk => active_tenant.id) # filter before any ordering (invariant 2)
          elsif TenancyDable::Scoped.require_tenant_in_context?
            raise TenancyDable::NoTenantError,
              "#{klass.name} was queried with no current tenant while require_tenant is active"
          else
            extending(TenancyDable::BuiltWithoutTenant) # fail-open default
          end
        end

        # Create refusal (§16.2): a new record whose fk names a tenant other than
        # the current one raises. Prepended so it runs before every validator
        # (a uniqueness check would otherwise read first and raise the read
        # error); the `before_create` twin covers `save(validate: false)`.
        before_validation(on: :create, prepend: true) { tenancy_refuse_foreign_tenant!(fk) }
        before_create(prepend: true) { tenancy_refuse_foreign_tenant!(fk) }

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

            errors.add(reflection.name, :cross_tenant)
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

    private

    # The create-refusal rule (§16.2, FROZEN). Ids only in the message (invariant 6).
    def tenancy_refuse_foreign_tenant!(fk)
      return if self[fk].blank? # blank: the auto-assign decides
      return if TenancyDable::Current.tenant_scope_disabled # without_tenant
      return unless (active_tenant = TenancyDable.current_tenant)
      return if self[fk].to_s == active_tenant.id.to_s

      raise TenancyDable::CrossTenantWriteError,
        "refusing to create #{self.class.name} in tenant ##{self[fk]} while acting in " \
        "tenant ##{active_tenant.id}; enter the tenant with TenancyDable.with_tenant"
    end
  end
end
