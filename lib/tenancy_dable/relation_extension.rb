# frozen_string_literal: true

module TenancyDable
  # Bulk-write guard, prepended to `ActiveRecord::Relation` by the railtie
  # (DESIGN.md §5.2). `update_all` / `delete_all` / `destroy_all` skip the
  # default scope's SQL `WHERE`, so without this a stray bulk write could touch
  # every tenant's rows. The guard refuses any bulk write on a tenant-scoped
  # relation that is not provably pinned to the current tenant.
  #
  # Guard rule (FROZEN, §5.2):
  #   * pass through models that are not tenant-scoped;
  #   * pass through inside `TenancyDable.without_tenant` (explicit bypass);
  #   * otherwise raise `BulkWriteError` when there is no current tenant, or when
  #     the relation's `tenant_fk` is not equality-pinned to that tenant's id.
  module RelationExtension
    def update_all(...)
      tenancy_guard_bulk_write!
      super
    end

    def delete_all(...)
      tenancy_guard_bulk_write!
      super
    end

    def destroy_all(...)
      tenancy_guard_bulk_write!
      super
    end

    private

    def tenancy_guard_bulk_write!
      return unless klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?
      return if TenancyDable::Current.tenant_scope_disabled

      active_tenant = TenancyDable.current_tenant
      if active_tenant.nil?
        raise TenancyDable::BulkWriteError,
          "refusing to bulk-write #{klass.name} with no current tenant " \
          "(wrap in TenancyDable.without_tenant to override)"
      end

      fk = TenancyDable.configuration.tenant_fk
      scoped_id = where_values_hash[fk.to_s]
      unless !scoped_id.nil? && scoped_id.to_s == active_tenant.id.to_s
        raise TenancyDable::BulkWriteError,
          "refusing to bulk-write #{klass.name} not scoped to the current tenant " \
          "(##{active_tenant.id}); wrap in TenancyDable.without_tenant to override"
      end
    end
  end
end
