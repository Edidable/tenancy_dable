# frozen_string_literal: true

module TenancyDable
  # Guards `insert_all` / `insert_all!` / `insert` / `upsert_all` / `upsert`
  # (DESIGN.md §16.2). They skip callbacks, so the create refusal never runs, and
  # `InsertAll` merges the RELATION's `scope_for_create` over every row: through
  # another tenant's association that is THAT tenant. Prepended to
  # `ActiveRecord::InsertAll` by the railtie, beside the Relation guard.
  #
  # Hooked on `initialize`, the one point shared by 7.1 (`model, inserts, ...`)
  # and 7.2+ (`relation, connection, inserts, ...`): the arguments are forwarded
  # untouched and the RESOLVED state (`@inserts`, `@scope_attributes`,
  # `@on_duplicate`, `@unique_by`) is read after `super`.
  #
  # Two rules, only for a tenant-scoped model with a current tenant and the
  # bypass off (no tenant and `without_tenant` pass through):
  #   * every row's effective fk (scope attribute over row value) is the current
  #     tenant's id;
  #   * an upsert resolves a `unique_by` index that includes the fk. Anything else
  #     (the primary key, an index spanning tenants, an adapter with no conflict
  #     target) lets the conflict UPDATE reach a row of another tenant, and the
  #     tenant column with it.
  module InsertAllExtension
    def initialize(...)
      super
      tenancy_guard_insert_all!
    end

    private

    def tenancy_guard_insert_all!
      return unless model.respond_to?(:tenant_scoped?) && model.tenant_scoped?
      return if TenancyDable::Current.tenant_scope_disabled
      return unless (active_tenant = TenancyDable.current_tenant)

      fk = TenancyDable.configuration.tenant_fk.to_s
      scope_attributes = @scope_attributes || {}

      inserts.each do |row|
        effective = scope_attributes.fetch(fk) { row[fk] }
        next if effective.to_s == active_tenant.id.to_s

        raise TenancyDable::CrossTenantWriteError,
          "refusing to insert #{model.name} rows into #{effective.nil? ? "no tenant" : "tenant ##{effective}"} " \
          "while acting in tenant ##{active_tenant.id}; enter the tenant with TenancyDable.with_tenant"
      end

      return unless on_duplicate == :update

      conflict_columns = Array(unique_by&.columns).map(&:to_s)
      return if conflict_columns.include?(fk)

      raise TenancyDable::CrossTenantWriteError,
        "refusing to upsert #{model.name} rows while acting in tenant ##{active_tenant.id}: " \
        "the conflict target (#{conflict_columns.empty? ? "none" : conflict_columns.join(", ")}) " \
        "must include #{fk}, or the update can reach another tenant's row"
    end
  end
end
