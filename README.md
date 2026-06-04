# TenancyDable

> Opinionated multi-workspace tenancy for Rails SaaS apps — the standards-propagation layer for the **edidable** skeleton family.

`tenancy_dable` extracts the tenancy stack from the edidable Rails SaaS skeleton into **one versioned gem** so every project you bootstrap inherits the same isolation guarantees, identity model, and authorization shape — and picks up fixes with a `bundle update` instead of a manual file-sync.

## Why a gem (and not copy-paste)

The row-scoping core is small, security-critical, and easy to get subtly wrong (a fail-*open* default scope leaks across tenants). Copy-pasting it into every app means every app drifts and every bug must be fixed N times. A gem makes the security boundary **one audited, versioned artifact** and `bundle update` the propagation mechanism.

## What it bundles

Four layers, one dependency:

| Layer | What you get |
|---|---|
| **Row-scoping engine** | `belongs_to_tenant`-style scoping, **fail-closed by default** (`require_tenant`), immutable `tenant_id`, bulk-write guard (`update_all`/`delete_all`), automatic ActiveJob tenant propagation, optional **Postgres RLS** hook |
| **Identity model** | global `User` ↔ `Membership` (role) ↔ `Tenant`; roles `owner`/`admin`/`member`; last-owner guard |
| **Resolution** | `/:tenant_slug` → tenant + **membership enforcement** (the piece `acts_as_tenant` / `rails-tenantify` don't ship) |
| **Authorization** | a Pundit `Context` (user + tenant + membership) + base policy with `same_tenant?` / `owner?` / `manager?` / `member?` and a fail-closed scope |

## How it differs from `acts_as_tenant` / `rails-tenantify`

Those gems are pure **row-scoping engines** — they scope `tenant_id` and propagate the current tenant, but have **no concept of memberships, roles, slug resolution, or authorization**. `tenancy_dable` is the whole multi-workspace layer; the row-scoping engine is just its foundation.

## Status

🚧 **Under construction.** This commit is the gem skeleton. The four layers, generators, test harness, and docs are built out via the autonomous Midgal plan in [`.midgal/PLAN.md`](.midgal/PLAN.md).

## Installation (target API)

```ruby
# Gemfile
gem "tenancy_dable"
```

```bash
bin/rails generate tenancy_dable:install
bin/rails db:migrate
```

## Configuration (target API)

```ruby
# config/initializers/tenancy_dable.rb
TenancyDable.configure do |config|
  config.tenant_model     = "Tenant"
  config.user_model       = "User"
  config.membership_model = "Membership"
  config.roles            = %w[owner admin member]
  config.require_tenant   = ->(*) { ActiveSupport::ExecutionContext.respond_to?(:to_h) } # fail-closed on web
  config.rls              = false # set true to emit `SET app.tenant_id = ...` on tenant change
end
```

## Development

```bash
bin/setup          # bundle install
bundle exec rake   # rspec + standard
```

## License

[MIT](LICENSE.txt) © 2026 Lucas Guedes
