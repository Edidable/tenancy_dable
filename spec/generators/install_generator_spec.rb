# frozen_string_literal: true

require_relative "generator_helper"

# `tenancy_dable:install` is the one-shot host wiring step (PLAN.md §Generators,
# DESIGN.md §1). It must drop the configuration initializer, the `tenants` +
# `memberships` migrations, and a secure-by-default `ApplicationPolicy`, then be
# safe to re-run after a `bundle update` without duplicating or clobbering
# anything. Every example runs against a throwaway destination root (see
# generator_helper.rb for why these specs avoid the Combustion harness).
RSpec.describe TenancyDable::Generators::InstallGenerator do
  include GeneratorSpecHelpers

  let(:destination) { Dir.mktmpdir("tenancy_dable-install") }

  after { FileUtils.remove_entry(destination) if File.directory?(destination) }

  # A real host always has a routes file; seeding it lets us prove the route
  # scaffold is injected (and, below, injected only once).
  before do
    seed_routes(destination)
    run_generator(described_class, destination: destination)
  end

  describe "the files it installs" do
    it "writes the configuration initializer" do
      initializer = read_generated(destination, "config/initializers/tenancy_dable.rb")

      expect(initializer).to include("TenancyDable.configure")
      expect(valid_ruby?(initializer)).to be(true)
    end

    it "writes a single tenants migration (slug NOT NULL + unique)" do
      expect(migration_paths(destination, "create_tenants").size).to eq(1)

      content = migration_body(destination, "create_tenants")
      expect(content).to include("create_table :tenants")
      expect(content).to include("t.string :slug, null: false")
      expect(content).to include("add_index :tenants, :slug, unique: true")
      expect(valid_ruby?(content)).to be(true)
    end

    it "writes a single memberships migration (role + composite unique index)" do
      expect(migration_paths(destination, "create_memberships").size).to eq(1)

      content = migration_body(destination, "create_memberships")
      expect(content).to include("create_table :memberships")
      expect(content).to include("t.references :tenant")
      expect(content).to include("t.string :role, null: false")
      expect(content).to include("add_index :memberships, [:user_id, :tenant_id], unique: true")
      expect(valid_ruby?(content)).to be(true)
    end

    it "writes an ApplicationPolicy that subclasses the secure-by-default base" do
      policy = read_generated(destination, "app/policies/application_policy.rb")

      expect(policy).to include("class ApplicationPolicy < TenancyDable::Policy::Base")
      expect(valid_ruby?(policy)).to be(true)
    end

    # Fix A: the constant lives in TenancyDable::Policy, not in Base, so a host
    # whose specs say `ApplicationPolicy::Context.new(...)` only resolves it via
    # this alias. Generated, not shipped — the gem ships no ApplicationPolicy.
    it "aliases Context on the generated ApplicationPolicy so policy specs resolve it" do
      policy = read_generated(destination, "app/policies/application_policy.rb")

      expect(policy).to include("Context = TenancyDable::Policy::Context")
    end

    it "injects the slug-only tenant route scaffold once" do
      routes = read_generated(destination, "config/routes.rb")

      expect(routes).to include(described_class::ROUTE_MARKER)
      expect(routes).to include('scope "/:tenant_slug"')
    end
  end

  describe "idempotency (safe to re-run after a bundle update)" do
    it "does not raise on a second run" do
      expect { run_generator(described_class, destination: destination) }.not_to raise_error
    end

    it "adds no duplicate migrations" do
      run_generator(described_class, destination: destination)

      expect(migration_paths(destination, "create_tenants").size).to eq(1)
      expect(migration_paths(destination, "create_memberships").size).to eq(1)
    end

    it "creates no new files and clobbers none on re-run" do
      before_files = files_under(destination).sort

      run_generator(described_class, destination: destination)

      expect(files_under(destination).sort).to eq(before_files)
    end

    it "injects the route scaffold marker exactly once" do
      run_generator(described_class, destination: destination)

      routes = read_generated(destination, "config/routes.rb")
      expect(routes.scan(described_class::ROUTE_MARKER).size).to eq(1)
    end
  end
end
