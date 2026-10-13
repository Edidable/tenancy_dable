---
paths:
  - "spec/spec_helper.rb"
  - "spec/rails_helper.rb"
  - "spec/support/**"
  - "spec/internal/**"
  - "spec/contract_spec.rb"
  - "spec/schema_spec.rb"
  - ".rspec"
---
The suite boots a real tiny Rails app through Combustion (`spec/rails_helper.rb`); a spec needing the database, models or controllers requires `rails_helper`, a pure-lib spec requires only `spec_helper`.
The test database is one gitignored SQLite FILE per checkout, recreated at every boot: never run two rspec processes in the same checkout at once, and never switch it to `:memory:` (Combustion's connection churn discards the schema).
`spec/internal/config/application.rb` is inert (Combustion owns the application); framework toggles and app config go in the `Combustion.initialize!` block in `rails_helper.rb`.
Keep `config.eager_load = true`: models that bake predicates from `config.roles` (Membership) must load once against the default configuration, not lazily inside a spec that changed `roles`.
Opt-in seams (`tenancy_dable/channel`, `tenancy_dable/job`) are required explicitly by the harness or the spec, before `Combustion.initialize!` when a harness class mixes them in.
Do not add a db unique index on `widgets[tenant_id, name]`: it would mask `validates_uniqueness_to_tenant`, the system under test.
A new fixture table or column goes in `spec/internal/db/schema.rb` and gets a line in `spec/schema_spec.rb`; a throwaway model for it is defined inside the spec.
A resolver stub captures the record in a local, never an implicit-self `let` (`instance_exec` rebinds `self`).
The global `after` hook calls `Current.reset` and `reset_configuration!`: specs need no teardown for tenant or config state, and never reset through `current_tenant = nil` (it fires the audit and RLS hooks).
Toggling `ActiveSupport::IsolatedExecutionState.isolation_level` is process-global: save it and restore it in an `ensure`.
If you change the public surface (setting, error, symbol, signature), also change `spec/contract_spec.rb` and the matching `DESIGN.md` section in the same change.
A probe spec lives under gitignored `tmp/` and runs with `rspec -I spec --default-path spec tmp/<file>_spec.rb`.
Another Rails line locally: a separate Gemfile (`gemspec path:` plus a `rails` pin) selected by its own `BUNDLE_GEMFILE`; Rails 7.1 needs a Ruby below 3.4.
Narrative: docs/domains/testing.md
