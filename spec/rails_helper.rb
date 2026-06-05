# frozen_string_literal: true

# Boots a real (tiny) Rails application via Combustion so specs can exercise the
# gem against genuine ActiveRecord + ActionPack instead of mocks. Specs that
# need the database, models, or controllers `require "rails_helper"`; pure-lib
# specs stay on `spec_helper` only.

require "spec_helper" # also `require "tenancy_dable"`, so any future Railtie is
#                       registered before the application initializes.

require "combustion"
require "factory_bot"

# Frameworks the harness boots: ActiveRecord backs the scoping/identity specs;
# ActionController backs the slug-resolution specs (Phases 05/10). The block is
# Combustion's `setup_environment` hook — application-level config goes here
# (Combustion owns the Rails::Application; see spec/internal/config/application.rb).
Combustion.initialize! :active_record, :action_controller do
  # Eager-load the host app at boot so every model that mixes in a TenancyDable
  # concern is loaded ONCE, up front, against the DEFAULT configuration — exactly
  # as a real host loads its models AFTER its initializer sets `config.roles`
  # (DESIGN.md §6.2). Without this the harness lazily autoloads `Membership` on
  # first reference; if that first reference happens inside a spec that has
  # temporarily reconfigured `roles` (e.g. the config-driven-predicate examples),
  # the role predicates (`owner?`/`admin?`/`member?`) bake from the WRONG set and
  # stay wrong for the rest of the suite (an order-dependent failure). Eager
  # loading makes predicate generation deterministic and order-independent.
  config.eager_load = true
end

require "rspec/rails"

# Shared contexts, factories, and helpers.
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  # Each example runs inside a transaction that is rolled back afterwards, so
  # the in-memory database stays clean between examples.
  config.use_transactional_fixtures = true

  # `create(:tenant)` / `build(:widget)` etc. without the `FactoryBot.` prefix.
  config.include FactoryBot::Syntax::Methods

  # Single source of truth for tenancy-state cleanup between examples. Both
  # calls are guarded because the symbols land later (`Current` in Phase 02), so
  # they currently no-op. `Current.reset` clears tenant/membership/scope flags
  # directly — deliberately NOT via `TenancyDable.current_tenant = nil`, which
  # would run the audit-override + RLS hooks (a stray `SET app.tenant_id = NULL`
  # on SQLite). Resetting the configuration undoes any per-example tweaks
  # (e.g. a shared context overriding `current_user_resolver`).
  config.after do
    TenancyDable::Current.reset if defined?(TenancyDable::Current)
    TenancyDable.reset_configuration! if TenancyDable.respond_to?(:reset_configuration!)
  end
end
