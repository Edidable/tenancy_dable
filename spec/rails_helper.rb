# frozen_string_literal: true

# Boots a real (tiny) Rails application via Combustion so specs can exercise the
# gem against genuine ActiveRecord + ActionPack instead of mocks. Specs that
# need the database, models, or controllers `require "rails_helper"`; pure-lib
# specs stay on `spec_helper` only.

require "spec_helper" # also `require "tenancy_dable"`, so any future Railtie is
#                       registered before the application initializes.

require "combustion"
require "factory_bot"

# Opt-in Cable concern (v0.3.0): like a host that runs channels, the harness
# requires it EXPLICITLY — the gem entry point does not (Action Cable is an
# OPTIONAL dependency). Required BEFORE `Combustion.initialize!` because
# `config.eager_load` (below) loads the harness's channel classes at boot, and
# `TenantChannel` mixes this in at class-definition time. The concern names no
# Action Cable constant at load, so requiring it before Action Cable is safe.
require "tenancy_dable/channel"

# Frameworks the harness boots: ActiveRecord backs the scoping/identity specs;
# ActionController backs the slug-resolution specs (Phases 05/10); ActionCable
# backs the channel specs (v0.3.0 phase 03 — Combustion maps `:action_cable` to
# `action_cable/engine`). ActionCable must load before `require "rspec/rails"`
# below, so rspec-rails registers `type: :channel` (its ChannelExampleGroup is
# gated on `defined?(::ActionCable)`). The block is Combustion's
# `setup_environment` hook — application-level config goes here (Combustion owns
# the Rails::Application; see spec/internal/config/application.rb).
Combustion.initialize! :active_record, :action_controller, :action_cable do
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
