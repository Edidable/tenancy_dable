# frozen_string_literal: true

module TenancyDable
  # Declaration audit (DESIGN.md §16.3): proves every model either scopes itself
  # or says why it is global. Reads only class metadata and the schema: no rows,
  # and nothing is raised for a finding.
  module Audit
    KINDS = %i[undeclared global_with_tenant_fk scoped_without_index].freeze

    # `model` is the class; `kind` is one of KINDS.
    Finding = Data.define(:model, :kind, :message) do
      def to_s = "#{model.name}: #{message}"
    end

    # With no argument, eager-loads the host and audits every named model;
    # explicit `models` are audited as given (no eager load, no name filter).
    def self.run(models = nil)
      config = TenancyDable.configuration
      fk = config.tenant_fk.to_s

      audited = candidates(models).reject { |model| skip?(model, config) }
      scoped_tables = (audited + live_models).select { |m| m.tenancy_declaration&.kind == :scoped }.to_set(&:table_name)
      findings = audited.flat_map { |model| findings_for(model, fk, scoped_tables) }

      findings.sort_by { |f| [f.model.name.to_s, KINDS.index(f.kind)] }.freeze
    end

    def self.candidates(models)
      return Array(models) unless models.nil?

      ::Rails.application.eager_load! if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
      live_models
    end
    private_class_method :candidates

    # Every loaded, named model; drops anonymous classes and stale ones
    # (constant removed or reloaded). Never eager-loads.
    def self.live_models
      ActiveRecord::Base.descendants.select { |m| m.name.present? && m.name.safe_constantize.equal?(m) }
    end
    private_class_method :live_models

    def self.skip?(model, config)
      name = model.name.to_s
      model.abstract_class? ||
        sti_subclass?(model) || # its base class answers for the table
        config.audit_ignored_namespaces.any? { |ns| name == ns.to_s || name.start_with?("#{ns}::") } ||
        config.audit_allowed.key?(name)
    end
    private_class_method :skip?

    # Real STI only: a subclass that points at another table is its own model.
    def self.sti_subclass?(model)
      model.base_class != model && model.table_name == model.base_class.table_name
    end
    private_class_method :sti_subclass?

    def self.findings_for(model, fk, scoped_tables)
      declaration = model.tenancy_declaration
      found = []
      found << finding(model, :undeclared, "declares no tenancy; add belongs_to_tenant, or tenant_global because: \"...\"") if declaration.nil?

      if declaration&.kind == :global && model.table_exists? && model.column_names.include?(fk)
        if scoped_tables.include?(model.table_name)
          # allow_tenant_fk cannot excuse it: a scoped model reads the same rows.
          found << finding(model, :global_with_tenant_fk,
            "is declared tenant_global but shares its table with a tenant-scoped model")
        elsif !declaration.allow_tenant_fk
          found << finding(model, :global_with_tenant_fk,
            "is declared tenant_global but has a #{fk} column; scope it with belongs_to_tenant, " \
            "or pass allow_tenant_fk: true if it is deliberately unscoped")
        end
      end

      if declaration&.kind == :scoped && model.table_exists? && !fk_indexed?(model, fk)
        found << finding(model, :scoped_without_index, "is tenant-scoped but no index leads with #{fk}")
      end

      found
    end
    private_class_method :findings_for

    # A composite primary key or index leading with the fk counts.
    def self.fk_indexed?(model, fk)
      return true if Array(model.primary_key).first.to_s == fk

      model.connection_pool.with_connection { |c| c.indexes(model.table_name) }
        .any? { |index| Array(index.columns).first.to_s == fk }
    end
    private_class_method :fk_indexed?

    def self.finding(model, kind, message)
      Finding.new(model: model, kind: kind, message: message)
    end
    private_class_method :finding
  end
end
