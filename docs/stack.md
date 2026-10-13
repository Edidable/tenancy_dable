# Stack

> What `tenancy_dable` depends on and why. The ranges live in the gemspec and the supported lines live in the CI matrix; this file names the reasons, not the versions.

## Sources of Truth

The dependency ranges are those in [FILE:tenancy_dable.gemspec], and the supported Ruby and Rails lines are the matrix in [FILE:.github/workflows/ci.yml]. The gemspec's `required_ruby_version` and its Rails range are a promise that the CI matrix verifies, line by line. `Gemfile` reads the [CONFIG:RAILS_VERSION] environment variable to pin one Rails line for a matrix cell and resolves the newest Rails the gemspec allows when it is unset. The lockfile is gitignored, so a local `bundle install` and a CI run resolve independently (see `docs/domains/release.md`).

## Runtime Dependencies

- [GEM:activesupport] provides `CurrentAttributes` (the `Current` holder), `Concern`, `Notifications` (the bypass event) and the isolated execution state the fiber check reads.
- [GEM:activerecord] is the layer the scoping engine extends: the default scope, `Relation`, `InsertAll`, validations and callbacks.
- [GEM:actionpack] provides the controller that `Resolvable` prepends onto and the `params` it reads the slug from.
- [GEM:railties] provides the `Railtie` that wires every framework hook, the initializers, the rake task loader and the generators base.
- [GEM:pundit] provides the authorization framework the `Policy::Context` and `Policy::Base` are built for. It is a runtime dependency of the authorization layer: the generated `ApplicationPolicy` subclasses the gem's base policy, and a host's controllers hand a `Policy::Context` to Pundit. The gem itself requires it lazily, only for the `on_not_a_member = :not_authorized` branch.

ActiveJob and Action Cable ship with `rails` and are optional for the gem: [FILE:lib/tenancy_dable/job.rb] and [FILE:lib/tenancy_dable/channel.rb] are opt-in files, so a host that runs neither never loads them.

## Why Self-Contained

There is no third-party tenancy gem in the list on purpose: the scoping engine, the guards and the job propagation are the gem's own code (rationale in `docs/decisions.md`). That is why the runtime list holds only Rails and Pundit.

## Development Dependencies

- [GEM:rails] with the same range as the runtime frameworks, so the whole suite runs against a full Rails.
- [GEM:rspec] and [GEM:rspec-rails] are the test framework; rspec-rails registers the channel example group when Action Cable is loaded.
- [GEM:combustion] boots a tiny real Rails application from `spec/internal/` so the gem is exercised against genuine Active Record and Action Pack rather than mocks (see `docs/domains/testing.md`).
- [GEM:factory_bot] builds the harness records.
- [GEM:sqlite3] backs the harness database.
- [GEM:async] provides the fiber scheduler the isolation-check and carrier specs run a real reactor on. Its newest releases need a newer Ruby than the oldest supported line, so Bundler resolves an older release there.
- [GEM:standard] is the linter, run in a separate CI job and by the default rake task.

## What Is Not Here

The gem has [ABSENCE:no authentication dependency]: the acting user comes from `config.current_user_resolver`, which by default reads the host's top-level `Current.user`, so any authentication stack works. It has [ABSENCE:no Action Cable authentication]: connection-level identification stays the host's job. It has [ABSENCE:no database-specific dependency]: the optional RLS hook emits a configurable statement, and the harness runs on SQLite.
