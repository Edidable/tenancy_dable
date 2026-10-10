# frozen_string_literal: true

module TenancyDable
  # Marker (§16.1): the default scope returns the relation `extending` this
  # module when it is BUILT with no tenant filter (no current tenant, or inside
  # `without_tenant`), so a relation built that way and loaded later inside a
  # tenant is recognised as unfiltered. It has no methods; the classifier reads
  # it. `Model.unscoped` is never marked (documented residual).
  module BuiltWithoutTenant
  end

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
  #
  # The same prepend carries the read guard (§16.1); both consume one pin
  # classifier, `tenancy_pin_state`.
  module RelationExtension
    def update_all(updates)
      tenancy_guard_bulk_write!
      tenancy_refuse_fk_update!(updates)
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

    # Read hooks (§16.1): each runs the read guard, then the real query.
    def pluck(...)
      tenancy_guard_read!
      super
    end

    def exists?(...)
      tenancy_guard_read!
      super
    end

    def ids(...)
      tenancy_guard_read!
      super
    end

    def load_async(...)
      tenancy_guard_read!
      super
    end

    # `compute_cache_version` sends its own COUNT/MAX query, and `arel` is what a
    # relation embedded as a subquery / `from` / `with` is compiled through. Both
    # are public on Rails 7.1-8.1.
    def compute_cache_version(...)
      tenancy_guard_read!
      super
    end

    def arel(...)
      tenancy_guard_read!
      super
    end

    private

    def exec_queries(...)
      tenancy_guard_read!
      super
    end

    def perform_calculation(...)
      tenancy_guard_read!
      super
    end

    # Read guard (§16.1, FROZEN decision tree): refuse a load, calculation,
    # pluck, exists? or ids on a tenant-scoped relation whose tenant filter is
    # pinned to another tenant (or several) or was removed, while a tenant is
    # current. `config.guard_reads = false` restores the 0.4.0 behaviour.
    def tenancy_guard_read!
      return unless TenancyDable.configuration.guard_reads
      return unless klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?
      return if TenancyDable::Current.tenant_scope_disabled

      active_tenant = TenancyDable.current_tenant
      return if active_tenant.nil?

      state = tenancy_pin_state(active_tenant)
      return unless state == :other || state == :removed

      detail = if state == :other
        "pinned to tenant #{where_values_hash[TenancyDable.configuration.tenant_fk.to_s].inspect}"
      else
        "with the tenant filter removed"
      end
      raise TenancyDable::CrossTenantReadError,
        "refusing to read #{klass.name} #{detail} while acting in tenant " \
        "##{active_tenant.id}; enter the tenant with TenancyDable.with_tenant, " \
        "or wrap a deliberate cross-tenant read in TenancyDable.without_tenant"
    end

    def tenancy_guard_bulk_write!
      return unless klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?
      return if TenancyDable::Current.tenant_scope_disabled

      active_tenant = TenancyDable.current_tenant
      if active_tenant.nil?
        raise TenancyDable::BulkWriteError,
          "refusing to bulk-write #{klass.name} with no current tenant " \
          "(wrap in TenancyDable.without_tenant to override)"
      end

      unless tenancy_pin_state(active_tenant) == :current
        raise TenancyDable::BulkWriteError,
          "refusing to bulk-write #{klass.name} not scoped to the current tenant " \
          "(##{active_tenant.id}); wrap in TenancyDable.without_tenant to override"
      end
    end

    # `update_all(tenant_id: ...)` rewrites the tenant of rows the WHERE pins to the
    # current tenant (invariant 3). Only the Hash form names a column; a SQL
    # string stays a documented residual.
    def tenancy_refuse_fk_update!(updates)
      return unless updates.is_a?(Hash)
      return unless klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?
      return if TenancyDable::Current.tenant_scope_disabled

      fk = TenancyDable.configuration.tenant_fk.to_s
      return unless updates.keys.any? { |column| tenancy_column_name(column) == fk }

      raise TenancyDable::TenantImmutableError,
        "#{klass.name}##{fk} is immutable; a record's tenant cannot change after create"
    end

    # The one pin classifier both guards consume (§16.1), so what they reason
    # about cannot drift. `active_tenant` is non-nil. A pin to the current tenant
    # wins over a recorded removal (`rewhere(tenant_id: current)` reads only the
    # current tenant); a nil pin is :unpinned (the default scope still ANDs in).
    def tenancy_pin_state(active_tenant)
      fk = TenancyDable.configuration.tenant_fk.to_s
      values = where_values_hash
      pinned = values[fk]
      return :current if !pinned.nil? && pinned.to_s == active_tenant.id.to_s
      return :other unless pinned.nil?
      return :removed if is_a?(TenancyDable::BuiltWithoutTenant)
      return :removed if tenancy_fk_unscoped?(fk)

      # No equality on the fk at all: any top-level predicate that mentions it
      # (`!=`, `NOT`, a range, a subquery, an `or` Grouping) replaced the default
      # scope's equality. An explicit nil pin (`IS NULL`, an Equality) is the one
      # shape that stays :unpinned; `where_values_hash` also reports nil for a
      # subquery on the fk, which is not an Equality.
      tenancy_fk_in_where?(fk, nil_pin: values.key?(fk)) ? :removed : :unpinned
    end

    def tenancy_fk_unscoped?(fk)
      unscope_values.any? do |value|
        value == :where ||
          (value.is_a?(Hash) && tenancy_unscope_targets(value[:where]).any? { |column| tenancy_column_name(column) == fk })
      end
    end

    # `unscope(where: ...)` takes a column, a list, or a table-keyed Hash
    # (`{widgets: :tenant_id}`, `{"widgets" => ["tenant_id"]}`); `Array(hash)`
    # would turn the Hash into [key, value] pairs.
    def tenancy_unscope_targets(target)
      Array.wrap(target).flat_map do |entry|
        entry.is_a?(Hash) ? entry.values.flat_map { |columns| Array.wrap(columns) } : [entry]
      end
    end

    # A Symbol/String compares its last "."-separated segment ("widgets.tenant_id"
    # counts); an Arel attribute compares #name, which is how `rewhere` records.
    def tenancy_column_name(column)
      column.is_a?(Arel::Attributes::Attribute) ? column.name.to_s : column.to_s.split(".").last
    end

    # Reads `where_clause`, never `arel` (the `arel` hook runs this guard).
    def tenancy_fk_in_where?(fk, nil_pin:)
      ast = where_clause.ast
      top = ast.is_a?(Arel::Nodes::And) ? ast.children : [ast]
      top.any? do |node|
        !(nil_pin && node.is_a?(Arel::Nodes::Equality)) && tenancy_references_fk?(node, fk)
      end
    end

    # Duck-typed so it covers Rails 7.1 (Or < Binary: left/right) and 7.2+
    # (Or < Nary: children).
    def tenancy_references_fk?(node, fk)
      case node
      when Arel::Attributes::Attribute
        node.name.to_s == fk && node.relation.respond_to?(:name) && node.relation.name.to_s == klass.table_name
      when Arel::Nodes::HomogeneousIn
        tenancy_references_fk?(node.attribute, fk)
      when Array
        node.any? { |child| tenancy_references_fk?(child, fk) }
      else
        children = []
        children.concat(node.children) if node.respond_to?(:children)
        children << node.left << node.right if node.respond_to?(:left) && node.respond_to?(:right)
        children << node.expr if node.respond_to?(:expr)
        children.any? { |child| tenancy_references_fk?(child, fk) }
      end
    end
  end
end
