# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module TenancyDable
  module Generators
    # `rails generate tenancy_dable:install` — wires TenancyDable into a host app:
    # the configuration initializer, the `tenants` + `memberships` migrations, a
    # secure-by-default `ApplicationPolicy`, a `Current` attributes model, and the
    # tenant-scoped route scaffold (PLAN.md §Generators / DESIGN.md §1).
    #
    # IDEMPOTENT (safe to re-run): every step skips when its target already
    # exists, so re-running after a `bundle update` never duplicates a migration,
    # clobbers an edited initializer, or re-injects the route scaffold. Generators
    # live under `lib/generators` and are auto-discovered by Rails on demand — they
    # are never required at boot (DESIGN.md §2).
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Install TenancyDable: initializer, tenants + memberships migrations, ApplicationPolicy, Current attributes, and the tenant-scoped route scaffold."

      # The identity models the host must mix the concerns into, in graph order.
      IDENTITY_CONCERNS = {
        "Tenant" => "TenancyDable::TenantModel",
        "User" => "TenancyDable::UserModel",
        "Membership" => "TenancyDable::MembershipModel"
      }.freeze

      # Sentinel so the route scaffold is injected at most once (idempotency).
      ROUTE_MARKER = "# >>> TenancyDable tenant-scoped routes"

      # 1. config/initializers/tenancy_dable.rb — the full, commented DSL.
      def create_initializer
        create_file_unless_exists "initializer.rb", "config/initializers/tenancy_dable.rb"
      end

      # 2a. tenants (slug unique). Generated BEFORE memberships so its timestamp
      #     orders ahead of the memberships tenant foreign key.
      def create_tenants_migration
        create_migration_unless_exists "create_tenants.rb", "create_tenants"
      end

      # 2b. memberships (user_id, tenant_id, role; unique [user_id, tenant_id]).
      def create_memberships_migration
        create_migration_unless_exists "create_memberships.rb", "create_memberships"
      end

      # 3. app/policies/application_policy.rb < TenancyDable::Policy::Base.
      def create_application_policy
        create_file_unless_exists "application_policy.rb", "app/policies/application_policy.rb"
      end

      # 4. app/models/current.rb — CurrentAttributes carrying `:user`, which the
      #    default `current_user_resolver` reads. Only created when the host has
      #    no `Current` of its own; otherwise it is told to add `attribute :user`.
      def create_current_attributes
        if file_exists?("app/models/current.rb")
          say_status :skip, "app/models/current.rb exists — ensure it defines `attribute :user` (or set config.current_user_resolver)", :yellow
        else
          template "current.rb", "app/models/current.rb"
        end
      end

      # 5. a commented `scope "/:tenant_slug"` route scaffold, injected once.
      def insert_route_scaffold
        routes = "config/routes.rb"
        unless file_exists?(routes)
          say_status :skip, "#{routes} not found — nest tenant routes under `scope \"/:#{slug_param}\"` manually", :yellow
          return
        end

        if File.read(File.expand_path(routes, destination_root)).include?(ROUTE_MARKER)
          say_status :skip, "#{routes} already has the TenancyDable route scaffold", :yellow
          return
        end

        inject_into_file routes, route_scaffold, after: /\.routes\.draw do\n/
      end

      # 6. Tell the host how to finish wiring: include the identity concerns into
      #    existing models, or generate the ones it is missing.
      def show_post_install
        say ""
        say "TenancyDable installed. Finish wiring it up:", :green
        IDENTITY_CONCERNS.each do |model, concern|
          path = "app/models/#{model.underscore}.rb"
          if file_exists?(path)
            say "  - #{path} exists: add `include #{concern}` to #{model}.", :green
          else
            say "  - #{model} model not found: generate it, then add `include #{concern}`.", :yellow
          end
        end
        say "  - Membership must NEVER `include TenancyDable::Scoped` (it is queried before a tenant is known — DESIGN.md §5.3).", :yellow
        say "  - Scaffold tenant-scoped models with: bin/rails g tenancy_dable:model NAME field:type", :green
        say "  - Then run: bin/rails db:migrate", :green
        say ""
      end

      private

      def file_exists?(relative)
        File.exist?(File.expand_path(relative, destination_root))
      end

      # Copy a template unless the destination already exists — never overwrite a
      # host-edited file (the contract's "skip existing").
      def create_file_unless_exists(source, destination)
        if file_exists?(destination)
          say_status :skip, "#{destination} already exists", :yellow
        else
          template source, destination
        end
      end

      # Generate a migration unless one with the same base name already exists
      # (any timestamp prefix). `migration_exists?` is what makes re-runs safe even
      # across a Rails upgrade that would otherwise change the rendered body.
      def create_migration_unless_exists(source, name)
        dir = File.expand_path(db_migrate_path, destination_root)
        if (existing = self.class.migration_exists?(dir, name))
          say_status :skip, "#{name} migration already exists (#{File.basename(existing)})", :yellow
        else
          migration_template source, File.join(db_migrate_path, "#{name}.rb")
        end
      end

      # The configured URL slug param (`:tenant_slug` by default). Read live so a
      # host that reconfigured it before installing still gets a matching scaffold.
      def slug_param
        TenancyDable.configuration.slug_param
      end

      # A commented routing block (two-space indented to sit inside `draw do`). It
      # is inert until the host uncomments it, and the marker guards re-injection.
      # Built line-by-line so the indentation is exact regardless of heredoc rules.
      def route_scaffold
        [
          "  #{ROUTE_MARKER} (uncomment and nest your workspace routes).",
          "  # Slug-only resolution (security invariant 5): resolve_tenant! looks the",
          "  # tenant up by params[:#{slug_param}] -- never by id.",
          "  # scope \"/:#{slug_param}\" do",
          "  #   # resources :widgets",
          "  # end",
          "  # <<< TenancyDable",
          ""
        ].join("\n")
      end
    end
  end
end
