# Testing

The gem is proven against a real, tiny Rails application booted by Combustion, not against mocks. This hub describes the harness, the fixture schema, the cleanup contract and the specs that lock the public surface.

## The harness

The harness boots through `spec/rails_helper.rb`, which runs [METHOD:Combustion.initialize!] with [CONFIG:frameworks=active_record, action_controller, action_cable]. The Combustion application lives in [FILE:spec/internal/] and owns the one `Rails::Application`; [FILE:spec/internal/config/application.rb] is intentionally inert and defines no application class, because a second subclass would conflict with Combustion's.

The `.rspec` file passes [CONFIG:--require spec_helper], documentation format and color, so every example loads `spec_helper.rb` first. [FILE:spec/spec_helper.rb] requires `tenancy_dable`, sets the `:expect` syntax, disables monkey patching and runs in [CONFIG:order=random] with the seed fed to `Kernel.srand`. A spec that needs no database, model or controller requires only `spec_helper`; a spec that does require `rails_helper`.

`rails_helper.rb` requires `spec_helper` first so the gem's Railtie is registered before the application initializes. It also requires [FILE:tenancy_dable/channel] explicitly, before `Combustion.initialize!`, because the Cable concern is opt-in (the gem entry point does not load it) and the harness's `TenantChannel` mixes it in at class-definition time. ActionCable is loaded before `require "rspec/rails"` so that rspec-rails registers the `type: :channel` example group, which is gated on `defined?(::ActionCable)`. The job seam is likewise opt-in, and a spec for it requires `tenancy_dable/job` itself.

## Eager load at boot

The Combustion block sets [CONFIG:config.eager_load=true]. Every harness model that mixes in a TenancyDable concern therefore loads once, up front, against the default configuration, as a real host loads its models after its initializer ran.

The same block sets [CONFIG:config.i18n.available_locales=[:en, :"pt-BR"]] so the gem's conditional `pt-BR` messages load; an English-only host does not get them (see `docs/domains/i18n.md`).

### Gotcha: Lazy autoload of Membership

[SYMPTOM:the role predicates `owner?`, `admin?` and `member?` are wrong for the rest of the suite in an order-dependent way]. [CAUSE:`MembershipModel` bakes its predicates from `config.roles` when the class loads, and with lazy autoload the first reference can happen inside a spec that temporarily reconfigured `roles`]. [FIX:keep `eager_load = true` so predicate generation is deterministic]. [RULE:a spec that changes `roles` must not be the first thing to load `Membership`].

## The database

The test database is [CONFIG:adapter=sqlite3] in a file, [FILE:spec/internal/db/combustion_test.sqlite3], declared in [FILE:spec/internal/config/database.yml] and gitignored. It is a file rather than `:memory:` on purpose: an in-memory SQLite database lives only as long as the one connection that opened it, Combustion churns connections while booting, and the connection holding the schema is discarded, so the test thread would see an empty database and every query would fail with "Could not find table". Combustion drops and recreates the file and reloads `db/schema.rb` on every boot, so nothing in it is ever committed.

There is exactly ONE such database per checkout. [RULE:never run two rspec processes in the same checkout at once]: they would recreate and write the same file. Parallel work needs a separate checkout (a worktree has its own `spec/internal/db/`). Examples run inside transactions ([CONFIG:use_transactional_fixtures=true]) that roll back after each example.

## The fixture schema and models

[FILE:spec/internal/db/schema.rb] defines the tables the suite runs against, and [FILE:spec/schema_spec.rb] proves its shape: the tables exist, `tenants.slug` is NOT NULL and unique, membership uniqueness is on `[user_id, tenant_id]`, `widgets.parent_id` is a nullable self reference, `gadgets.tenant_id` is indexed and `unindexed_records.tenant_id` is not.

The models in [FILE:spec/internal/app/models/] are the systems under test:

- [FILE:widget.rb] is the main scoped model: `Scoped`, `belongs_to_tenant`, a self-referential `parent` (it exercises the cross-tenant `belongs_to` validation) and `validates_uniqueness_to_tenant :name`.
- [FILE:gadget.rb] is scoped with no uniqueness validation, so a refusal is proven independent of whatever validators a model carries.
- [FILE:tenant.rb], [FILE:user.rb] and [FILE:membership.rb] include the identity concerns. `Tenant` also declares `has_many :widgets`, `has_one :first_widget` and `has_many :gadgets`, the association shapes the read guard refuses while acting in another tenant.
- `Membership` never includes `Scoped`: it is queried before any tenant is current.

[ABSENCE:no db-level unique index on `widgets[tenant_id, name]`] is deliberate, because a database constraint would mask `validates_uniqueness_to_tenant`, which is the thing under test. The `unindexed_records` table has no model file; the audit specs define throwaway models on it, which is how the index check is exercised. The harness also carries controllers (`WidgetsController`, `ReportsController`), `TenantChannel` with its `ApplicationCable` base classes, routes, and an `en.yml`.

## Factories and shared contexts

[FILE:spec/support/factories.rb] defines factories for tenant, user, membership, widget and gadget. They assign foreign keys directly and expose `user:`, `tenant:` and `parent:` as transient overrides, so a call like `create(:widget, tenant: a)` works. [FILE:spec/rails_helper.rb] includes `FactoryBot::Syntax::Methods`, so factories are called without the `FactoryBot.` prefix.

[FILE:spec/support/shared_contexts.rb] provides two contexts. `"with tenant"` defines `let(:tenant)` and makes it the current tenant through the facade. `"with authenticated user"` defines `let(:user)` and sets `current_user_resolver` to a lambda over a LOCAL variable, for the reason in the gotcha below. Every file under `spec/support/` is required by `rails_helper`.

### Gotcha: An implicit-self `let` inside the resolver

[SYMPTOM:the resolver blows up with an undefined `user`]. [CAUSE:the controller runs the resolver with `instance_exec`, which rebinds `self`, so a `let` resolves against the controller]. [FIX:capture the record in a local before building the lambda]. [RULE:a resolver stub in a spec never leans on an implicit-self helper].

## Cleanup after each example

A global `after` hook in `rails_helper.rb` is the single source of truth for tenancy-state cleanup. It calls [METHOD:TenancyDable::Current.reset] and [METHOD:TenancyDable.reset_configuration!]. `Current.reset` clears tenant, membership and scope flags directly and deliberately does not go through `TenancyDable.current_tenant = nil`, because that would run the audit-override and RLS hooks (a stray `SET app.tenant_id = NULL`). Resetting the configuration undoes per-example tweaks such as an overridden `current_user_resolver`. [RULE:a spec never needs its own teardown for tenant or configuration state; it relies on this hook], and a spec that changes global state outside these two (the isolation level, a constant, a stubbed class) restores it in an `ensure`.

## Toggling the isolation level

Specs that need fiber isolation set [METHOD:ActiveSupport::IsolatedExecutionState.isolation_level=] to `:fiber` around a `Sync do ... end` block and restore the previous level in an `ensure` (see `spec/facade/snapshot_spec.rb` and `spec/facade/isolation_check_spec.rb`). Other isolation-check examples stub `isolation_level` with `allow(...).to receive` instead of changing it. The fiber specs depend on the `async` development dependency.

### Gotcha: The isolation level leaks

[SYMPTOM:later examples see fiber-keyed `Current` state or an unexpected isolation-check result]. [CAUSE:`isolation_level` is process-global and survives the example]. [FIX:save the level before the toggle and restore it in `ensure`]. [RULE:never set the level without the restoring `ensure`].

## The contract spec

[FILE:spec/contract_spec.rb] locks the public surface: the configuration settings and their defaults, the facade, `Current`, the declared signatures of the guards, declarations, audit, snapshot, identity, resolution and authorization symbols, the error hierarchy, `Railtie.locale_files`, the generators, the job seam and the channel seam. It proves SHAPE; layer specs prove behaviour. It requires the opt-in job and channel files, so it covers them.

It derives the settings check from the code (it counts `Configuration`'s writers), so adding or removing a setting without updating it fails; the error, facade, hook and helper checks are explicit lists: removing a listed symbol fails them, a new one passes until it is added. [RULE:a change to the public surface edits the contract spec in the same change], together with the matching `DESIGN.md` section (see `docs/domains/errors.md` and `docs/domains/configuration.md`). The spec names the frozen sections in its `describe` titles.

## Throwaway probe specs

A spec written to test a hypothesis, not to stay, goes under the gitignored `tmp/` directory and is run with [CONFIG:rspec -I spec --default-path spec tmp/<name>_spec.rb]. `-I spec` makes `require "rails_helper"` resolve, and `--default-path spec` keeps rspec from treating `tmp/` as the default spec directory. A probe that earns its keep moves into the matching `spec/<layer>/` directory.

## Running another Rails line locally

The default lockfile (gitignored) resolves the newest Rails the gemspec allows. To run the suite against another line, use a separate Gemfile whose `gemspec path:` points at the repository and which pins `rails`, and select it with a separate `BUNDLE_GEMFILE`, so the default lockfile stays untouched. The CI matrix in `.github/workflows/ci.yml` is the list of supported lines (see `docs/domains/release.md`). Rails 7.1 needs a Ruby below 3.4, which is why the matrix excludes that cell.
