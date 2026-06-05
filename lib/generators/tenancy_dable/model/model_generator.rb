# frozen_string_literal: true

require "rails/generators/named_base"
require "rails/generators/active_record"

module TenancyDable
  module Generators
    # `rails generate tenancy_dable:model NAME field:type ...` — a tenant-scoped
    # model. Like `rails g model`, but the generated class `include`s
    # TenancyDable::Scoped and declares `belongs_to_tenant`, and the migration
    # prepends the tenant foreign key (`tenant_id` by default) with its index
    # (PLAN.md §Generators / DESIGN.md §5).
    #
    # No `check_class_collision` on purpose: it inspects the RUNTIME constant, not
    # the destination, which would wrongly abort when generating a model whose name
    # is already loaded in the same process (e.g. the spec harness in Phase 12).
    class ModelGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

      class_option :timestamps, type: :boolean, default: true, desc: "Add created_at/updated_at columns"

      desc "Generate a tenant-scoped model (include TenancyDable::Scoped + belongs_to_tenant) and its migration."

      def create_migration_file
        migration_template "migration.rb", File.join(db_migrate_path, "create_#{table_name}.rb")
      end

      def create_model_file
        template "model.rb", File.join("app/models", class_path, "#{file_name}.rb")
      end

      private

      # The base class for the generated model. Kept simple (the contract names no
      # `--parent` option); hosts edit the result if they use a different base.
      def parent_class_name
        "ApplicationRecord"
      end

      # The tenant `belongs_to` / column name derived from the configured foreign
      # key: `:tenant_id` -> `tenant` (so `t.references :tenant` writes `tenant_id`
      # plus its index, matching what `belongs_to_tenant` scopes by).
      def tenant_reference_name
        TenancyDable.configuration.tenant_fk.to_s.delete_suffix("_id")
      end

      # The non-reference attributes that requested an index (references carry
      # their own). Mirrors Rails' own model migration template.
      def attributes_with_index
        attributes.select { |attribute| !attribute.reference? && attribute.has_index? }
      end
    end
  end
end
