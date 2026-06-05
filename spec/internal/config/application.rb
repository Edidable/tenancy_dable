# frozen_string_literal: true

# NOTE: Combustion builds and owns the Rails application object for this test
# harness — `Combustion::Application < Rails::Application`, created inside
# `Combustion.initialize!` (see spec/rails_helper.rb). Combustion does NOT load
# this file, and a second `Rails::Application` subclass here would conflict with
# the one Combustion creates. This file is therefore intentionally INERT.
#
# It exists only to mirror a conventional Rails layout and to document where the
# harness's configuration actually lives:
#
#   * Framework toggles / per-run app config → the block passed to
#     `Combustion.initialize!` in spec/rails_helper.rb (Combustion's
#     `setup_environment` hook).
#   * Schema   → spec/internal/db/schema.rb       (DESIGN.md §8)
#   * Routes   → spec/internal/config/routes.rb
#   * Database → spec/internal/config/database.yml (sqlite, in-memory)
#
# Do not define a Rails::Application in this file.
