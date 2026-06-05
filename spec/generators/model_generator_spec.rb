# frozen_string_literal: true

require_relative "generator_helper"

# `tenancy_dable:model NAME field:type ...` scaffolds a tenant-scoped model
# (PLAN.md §Generators, DESIGN.md §5): the class `include`s TenancyDable::Scoped
# and declares `belongs_to_tenant`, and the migration prepends the tenant foreign
# key (its column + index) ahead of the requested fields. Runs against a
# throwaway destination root (see generator_helper.rb).
RSpec.describe TenancyDable::Generators::ModelGenerator do
  include GeneratorSpecHelpers

  let(:destination) { Dir.mktmpdir("tenancy_dable-model") }

  after { FileUtils.remove_entry(destination) if File.directory?(destination) }

  # These specs skip rails_helper, so they don't inherit its configuration-reset
  # after-hook. The tenant_fk example below reconfigures TenancyDable; reset here
  # so that change can't leak into another example (rebuilds the frozen defaults).
  after { TenancyDable.reset_configuration! if TenancyDable.respond_to?(:reset_configuration!) }

  describe "the generated model" do
    before { run_generator(described_class, ["Widget", "name:string"], destination: destination) }

    let(:model) { read_generated(destination, "app/models/widget.rb") }

    it "mixes in the TenancyDable::Scoped concern" do
      expect(model).to include("include TenancyDable::Scoped")
    end

    it "declares belongs_to_tenant" do
      expect(model).to include("belongs_to_tenant")
    end

    it "subclasses ApplicationRecord and is valid Ruby" do
      expect(model).to include("class Widget < ApplicationRecord")
      expect(valid_ruby?(model)).to be(true)
    end
  end

  describe "the generated migration" do
    before { run_generator(described_class, ["Widget", "name:string"], destination: destination) }

    let(:migration) { migration_body(destination, "create_widgets") }

    it "creates exactly one migration for the model" do
      expect(migration_paths(destination, "create_widgets").size).to eq(1)
    end

    it "adds the tenant_id reference and its index first" do
      # `t.references :tenant` writes the tenant_id column AND its index in one
      # line — that pairing is the "tenant_id + index" the contract mandates.
      expect(migration).to include("create_table :widgets")
      expect(migration).to include("t.references :tenant, null: false, foreign_key: true")
    end

    it "carries the requested field columns" do
      expect(migration).to include("t.string :name")
    end

    it "is valid Ruby" do
      expect(valid_ruby?(migration)).to be(true)
    end
  end

  describe "honoring the configured tenant_fk" do
    # The tenant reference is derived from config.tenant_fk, not hard-coded:
    # point it at a different column and the migration follows. (reset_configuration!
    # in the global after-hook restores the default for later examples.)
    it "references the configured foreign key instead of a literal :tenant" do
      TenancyDable.configure { |config| config.tenant_fk = :workspace_id }

      run_generator(described_class, ["Widget", "name:string"], destination: destination)
      migration = migration_body(destination, "create_widgets")

      expect(migration).to include("t.references :workspace, null: false, foreign_key: true")
      expect(migration).not_to include("t.references :tenant,")
      expect(valid_ruby?(migration)).to be(true)
    end
  end
end
