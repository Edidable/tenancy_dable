# frozen_string_literal: true

module TenancyDable
  # Marker (§16.1): the default scope returns the relation `extending` this
  # module when it is BUILT with no tenant filter (no current tenant, or inside
  # `without_tenant`), so a relation built that way and loaded later inside a
  # tenant is recognised as unfiltered. It has no methods; the classifier reads
  # it. `Model.unscoped` is never marked (documented residual).
  module BuiltWithoutTenant
  end

  # A where-clause right side that is not a bound value (§16.1).
  NOT_LITERAL = Object.new.freeze
  private_constant :NOT_LITERAL

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
        "pinned to tenant #{tenancy_other_pin(TenancyDable.configuration.tenant_fk.to_s, active_tenant).inspect}"
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
      return unless updates.keys.any? { |column| tenancy_fk_column?(column, fk) }

      raise TenancyDable::TenantImmutableError,
        "#{klass.name}##{fk} is immutable; a record's tenant cannot change after create"
    end

    # The one pin classifier both guards consume (§16.1), so what they reason
    # about cannot drift. `active_tenant` is non-nil. It reads the fk's LITERAL
    # pins from the where clause, never `where_values_hash` (which raises on
    # `lower(name) = ?` and reports nil for a non-literal equality), in order:
    #   * a literal pin to another tenant, or a list holding one, is :other;
    #   * a literal pin to the current tenant is :current: the conjunct confines
    #     the rows (`rewhere(tenant_id: current)`, an eager_load join that ANDs
    #     `tenant_id = tenants.id` beside it);
    #   * the built-without-tenant marker and `unscope` are :removed;
    #   * any other top-level predicate that mentions the fk (`!=`, `NOT`, a
    #     range, a subquery, an `or` Grouping) replaced the default scope's
    #     equality and is :removed; an explicit nil pin (`IS NULL`) is the one
    #     shape that stays :unpinned.
    def tenancy_pin_state(active_tenant)
      fk = TenancyDable.configuration.tenant_fk.to_s
      pins = tenancy_fk_literal_pins(fk)
      return :other if pins.any? { |pin| tenancy_other_pin?(pin, active_tenant) }
      return :current if pins.any? { |pin| tenancy_current_pin?(pin, active_tenant) }
      # extending_values survives `dup`, which drops the singleton extension
      return :removed if is_a?(TenancyDable::BuiltWithoutTenant) || extending_values.include?(TenancyDable::BuiltWithoutTenant)
      return :removed if tenancy_fk_unscoped?(fk)

      tenancy_fk_in_where?(fk) ? :removed : :unpinned
    end

    # The literal values of the top-level fk equalities: a value, or a list of
    # values. A right side that is not a bound value (a subquery, a column, an
    # `Arel.sql` literal) is not a pin.
    def tenancy_fk_literal_pins(fk)
      tenancy_equality_nodes(where_clause.ast).filter_map do |node|
        next unless tenancy_fk_attribute?(node.left, fk)

        value = tenancy_node_value(node.right)
        [value] unless value.equal?(NOT_LITERAL)
      end.map(&:first)
    end

    def tenancy_equality_nodes(node)
      return [] if node.nil? || node.is_a?(String)
      return node.children.flat_map { |child| tenancy_equality_nodes(child) } if node.is_a?(Arel::Nodes::And)

      (node.respond_to?(:equality?) && node.equality?) ? [node] : []
    end

    def tenancy_node_value(node)
      if node.respond_to?(:value_before_type_cast)
        node.value_before_type_cast
      elsif node.is_a?(Array)
        values = node.map { |value| tenancy_node_value(value) }
        (values.any? { |value| value.equal?(NOT_LITERAL) }) ? NOT_LITERAL : values
      else
        NOT_LITERAL
      end
    end

    def tenancy_fk_attribute?(node, fk)
      node.is_a?(Arel::Attributes::Attribute) && node.name.to_s == fk &&
        node.relation.respond_to?(:name) && node.relation.name.to_s == klass.table_name
    end

    # A list is :current when it reads nothing or only the current tenant (`[]`,
    # `[current, current]`, `[current, nil]`); any other list names another tenant.
    def tenancy_current_pin?(pin, active_tenant)
      return pin.all? { |value| value.nil? || value.to_s == active_tenant.id.to_s } if pin.is_a?(Array)

      !pin.nil? && pin.to_s == active_tenant.id.to_s
    end

    def tenancy_other_pin?(pin, active_tenant)
      return !tenancy_current_pin?(pin, active_tenant) if pin.is_a?(Array)

      !pin.nil? && pin.to_s != active_tenant.id.to_s
    end

    def tenancy_other_pin(fk, active_tenant)
      tenancy_fk_literal_pins(fk).find { |pin| tenancy_other_pin?(pin, active_tenant) }
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

    # An alias (`alias_attribute :workspace_id, :tenant_id`) resolves to its
    # column, and column names compare case-insensitively (SQLite and MySQL do).
    def tenancy_fk_column?(column, fk)
      name = tenancy_column_name(column)
      klass.attribute_aliases.fetch(name, name).casecmp?(fk)
    end

    # A Symbol/String compares its last "."-separated segment ("widgets.tenant_id"
    # counts); an Arel attribute compares #name, which is how `rewhere` records.
    def tenancy_column_name(column)
      column.is_a?(Arel::Attributes::Attribute) ? column.name.to_s : column.to_s.split(".").last
    end

    # Any top-level predicate on the fk other than an explicit literal nil pin
    # (`IS NULL`). Reads `where_clause`, never `arel` (the `arel` hook runs this
    # guard).
    def tenancy_fk_in_where?(fk)
      ast = where_clause.ast
      top = ast.is_a?(Arel::Nodes::And) ? ast.children : [ast]
      top.any? do |node|
        nil_pin = node.is_a?(Arel::Nodes::Equality) && tenancy_fk_attribute?(node.left, fk) && tenancy_node_value(node.right).nil?
        !nil_pin && tenancy_references_fk?(node, fk)
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
