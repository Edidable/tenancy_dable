# TenancyDable

> Opinionated multi-workspace tenancy for Rails SaaS apps — the standards-propagation layer for the **edidable** skeleton family.

`tenancy_dable` extracts the tenancy stack from the edidable Rails SaaS skeleton into **one versioned gem** so every project you bootstrap inherits the same isolation guarantees, identity model, and authorization shape — and picks up fixes with a `bundle update` instead of a manual file-sync.

It is **not** a bare row-scoper. It bundles four layers behind one dependency: a fail-closed row-scoping engine, a memberships/roles identity model, slug-based tenant resolution with membership enforcement, and a Pundit authorization context.

- **New to the gem?** Start with [Installation](#installation) → [Configuration](#configuration) → [The four layers](#the-four-layers).
- **Migrating an existing skeleton app, or bumping the gem across projects?** See [UPGRADING.md](UPGRADING.md).
- **The full per-symbol contract** (frozen public surface, security invariants, load graph) lives in [DESIGN.md](DESIGN.md).

## Why a gem (and not copy-paste)

The row-scoping core is small, security-critical, and easy to get subtly wrong — a fail-*open* default scope leaks rows across tenants. Copy-pasting it into every app means every app drifts and every bug must be fixed N times. A gem makes the security boundary **one audited, versioned artifact** and `bundle update` the propagation mechanism.

## What it bundles

Four layers, one dependency:

| Layer | What you get |
|---|---|
| **Row-scoping engine** | `belongs_to_tenant` scoping, **fail-closed when configured** (`require_tenant`), immutable `tenant_id`, a bulk-write guard on `update_all`/`delete_all`/`destroy_all`, opt-in ActiveJob tenant propagation, and an optional **Postgres RLS** hook |
| **Identity model** | global `User` ↔ `Membership` (role) ↔ `Tenant`; roles `owner`/`admin`/`member`; generated role predicates; last-owner guard |
| **Resolution** | `/:tenant_slug` → tenant + **membership enforcement** (the piece `acts_as_tenant` / `rails-tenantify` don't ship) |
| **Authorization** | a Pundit `Context` (user + tenant + membership) and a secure-by-default base policy with `same_tenant?` / `owner?` / `manager?` / `member?` and a fail-closed scope |

## Compatibility

- **Ruby** ≥ 3.2
- **Rails** ≥ 7.1, < 9 (`activesupport`, `activerecord`, `actionpack`, `railties`)
- **Pundit** ≥ 2.3

ActiveJob and Action Cable are **optional** — needed only if you opt into [tenant propagation into background jobs](#opt-in-activejob-tenant-propagation) or [Action Cable tenant resolution](#opt-in-action-cable-tenant-resolution). Both ship with `rails`, so a host already has them.

## Installation

```ruby
# Gemfile
gem "tenancy_dable", "~> 0.1.0"
```

```bash
bundle install
bin/rails generate tenancy_dable:install
bin/rails db:migrate
```

### What `tenancy_dable:install` creates

The install generator is **idempotent** — every step skips when its target already exists, so re-running it after a `bundle update` never duplicates a migration or clobbers an edited file.

| It writes | Purpose |
|---|---|
| `config/initializers/tenancy_dable.rb` | The full configuration DSL, every setting commented with its default. |
| `db/migrate/*_create_tenants.rb` | `tenants` table with a **unique** `slug`. |
| `db/migrate/*_create_memberships.rb` | `memberships` (`user_id`, `tenant_id`, `role`) with a unique `[user_id, tenant_id]` index. |
| `app/policies/application_policy.rb` | `ApplicationPolicy < TenancyDable::Policy::Base` (+ its `Scope`). |
| `app/models/current.rb` | A `Current < ActiveSupport::CurrentAttributes` with `attribute :user` — only if you don't already have one (otherwise you're told to add `attribute :user`). |
| `config/routes.rb` | A commented `scope "/:tenant_slug"` route scaffold, injected once. |

After it runs it prints the remaining manual step: **mix the identity concerns into your models** (`include TenancyDable::TenantModel` / `UserModel` / `MembershipModel`). It does not edit your existing models for you.

## Configuration

Everything is set in `config/initializers/tenancy_dable.rb`:

```ruby
TenancyDable.configure do |config|
  config.tenant_model     = "Tenant"
  config.user_model       = "User"
  config.membership_model = "Membership"
  config.roles            = %w[owner admin member]
  config.require_tenant   = true   # fail closed: an unscoped query on a scoped model raises
end
```

`configure` validates the result and raises `TenancyDable::ConfigurationError` on bad config (empty `roles`, `manager_roles` not a subset of `roles`, or a blank model name).

### Full configuration reference

| Setting | Default | Meaning |
|---|---|---|
| `tenant_model` | `"Tenant"` | Workspace model name (resolved to a constant lazily). |
| `user_model` | `"User"` | Global identity model name. |
| `membership_model` | `"Membership"` | The user ↔ tenant join model name. |
| `roles` | `%w[owner admin member]` | Ordered highest-first. One predicate per role is generated on the membership; `roles.first` is the owner role. |
| `manager_roles` | `%w[owner admin]` | The "can manage the workspace" set; must be a subset of `roles`. |
| `tenant_fk` | `:tenant_id` | Foreign key on tenant-scoped models. |
| `slug_param` | `:tenant_slug` | URL param tenant resolution reads. |
| `require_tenant` | `false` | Boolean **or** callable. When truthy-in-context, an unscoped query on a scoped model raises `NoTenantError` instead of returning every tenant's rows (**fail closed**). A callable is evaluated per query. |
| `rls` | `false` | When true, emit `rls_statement` against the connection on every tenant change. |
| `rls_statement` | `->(tenant) { "SET app.tenant_id = #{ActiveRecord::Base.connection.quote(tenant&.id)}" }` | The SQL emitted when `rls` is on. |
| `audit_overrides` | `:log` | Behaviour when `current_tenant` is reassigned to a **different** tenant mid-request: `:log` (tenant ids only — never payloads), `:raise` (`TenantOverrideError`), or `:ignore`. |
| `on_tenant_not_found` | `:raise` | When a slug matches no tenant: `:raise` (`ActiveRecord::RecordNotFound`) or `:null` (proceed with no tenant in context). |
| `on_not_a_member` | `:not_a_member_error` | When the acting user is authenticated but **not** a member of the resolved tenant: `:not_a_member_error` (raise `NotAMemberError` — default, today's behavior) / `:not_authorized` (raise `Pundit::NotAuthorizedError`, required lazily — reuse an existing `rescue_from Pundit::NotAuthorizedError`) / a callable `->(tenant)` run with `instance_exec` in the controller (redirect, `head :forbidden`, raise your own). Membership stays required in every mode. |
| `current_user_resolver` | `-> { (defined?(::Current) && ::Current.respond_to?(:user)) ? ::Current.user : nil }` | How resolution finds the acting user (auth-agnostic). Run with `instance_exec` in the controller, so `-> { current_user }` works for Devise. |

> **Default is fail-OPEN.** As shipped, a scoped query with no active tenant returns `all`. Set `require_tenant = true` (or a per-query callable) to make those queries raise instead. The web request path is always scoped because [resolution](#3-slug-resolution) establishes a tenant before your action runs; `require_tenant` is the backstop for jobs, consoles, and rake tasks.

## The four layers

### 1. Row-scoping engine

Include `TenancyDable::Scoped` and declare the model tenant-scoped:

```ruby
class Invoice < ApplicationRecord
  include TenancyDable::Scoped

  belongs_to_tenant                     # belongs_to :tenant, scopes by :tenant_id
  validates_uniqueness_to_tenant :number # unique WITHIN a workspace, not globally
end
```

What `belongs_to_tenant` installs:

```ruby
TenancyDable.with_tenant(workspace) do
  Invoice.all                  # => only `workspace`'s invoices (default_scope filters by tenant_id)
  inv = Invoice.create!(number: "A-1")
  inv.tenant_id                # => workspace.id   (auto-assigned on create)
  inv.update(tenant_id: other.id)  # => raises TenancyDable::TenantImmutableError
end

Invoice.update_all(state: "void")  # outside a tenant => raises TenancyDable::BulkWriteError
TenancyDable.without_tenant { Invoice.update_all(state: "void") }  # explicit bypass — allowed
```

- **Default scope filters by tenant before any ordering** (no cross-tenant read path).
- **`tenant_id` is immutable** after create (assignment-writer *and* `before_update` backstop).
- **Bulk writes are guarded.** `update_all` / `delete_all` / `destroy_all` raise `BulkWriteError` unless the relation is provably pinned to the current tenant; wrap in `TenancyDable.without_tenant { … }` to override.
- **Cross-tenant `belongs_to` is rejected** at validation: a scoped association pointing at another tenant's row adds a "belongs to a different tenant" error.

Context helpers on the `TenancyDable` facade:

```ruby
TenancyDable.current_tenant            # => the active workspace (or nil)
TenancyDable.current_tenant = workspace
TenancyDable.with_tenant(workspace) { … }  # set for the block, restore after (nesting-safe; returns block value)
TenancyDable.without_tenant { … }          # disable scoping for the block
TenancyDable.current_membership        # => the acting membership, or nil when it is not the current tenant's
TenancyDable.foreign_membership?       # => true when a membership is set but is not the current tenant's
```

### 2. Identity model

Mix the concerns into your three identity models:

```ruby
class Tenant < ApplicationRecord
  include TenancyDable::TenantModel        # memberships/users, slug generation + validation, #owners
end

class User < ApplicationRecord
  include TenancyDable::UserModel          # memberships/tenants, #membership_for, #member_of?
end

class Membership < ApplicationRecord
  include TenancyDable::MembershipModel    # role inclusion + predicates, owners/admins scopes, last-owner guard
  # NOTE: never `include TenancyDable::Scoped` here — Membership is queried BEFORE a tenant is
  # known (to discover which tenants a user belongs to). Scoping it would deadlock resolution.
end
```

```ruby
tenant.slug                  # auto-generated from `name`, unique, URL-safe (e.g. "acme-inc")
tenant.owners                # => Users holding the owner role in this tenant

user.membership_for(tenant)  # => the Membership, or nil
user.member_of?(tenant)      # => boolean

membership.owner?            # generated from config.roles (owner?/admin?/member?/…)
membership.manager?          # role ∈ config.manager_roles
Membership.owners            # scope: role == roles.first
Membership.admins            # scope: role ∈ manager_roles
```

The **last-owner guard** refuses to demote a workspace's only owner (`throw :abort`; the save fails, the row is unchanged). Demoting one of several owners is allowed.

### 3. Slug resolution

Nest tenant routes under the slug and call `resolve_tenant!`:

```ruby
# config/routes.rb
scope "/:tenant_slug" do
  resources :invoices
end
```

```ruby
class InvoicesController < ApplicationController
  resolve_tenant!   # before_action: find tenant by slug → enforce membership → publish current_tenant/membership

  def index
    @invoices = Invoice.all   # already scoped to the resolved tenant
  end
end
```

`resolve_tenant!` installs a `before_action` that:

1. finds the tenant via `find_by!(slug: params[:tenant_slug])` — **slug only, never an id from the URL**;
2. resolves the acting user via `current_user_resolver`;
3. requires `user.membership_for(tenant)` or raises `TenancyDable::NotAMemberError`;
4. publishes `TenancyDable.current_tenant` and `current_membership`.

It also overrides `default_url_options` to inject the active tenant's slug, so path/url helpers nested under `/:tenant_slug` can omit it. `resolve_tenant!` accepts the usual `before_action` options (`only:`, `except:`, `if:`, …).

### 4. Authorization

Policies decide on a `Policy::Context` (user + tenant + membership), not a bare user — the same user is an owner in one workspace and a non-member in another. Wire it through Pundit's `pundit_user`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  resolve_tenant!

  private

  def pundit_user
    TenancyDable.pundit_context(
      user: Current.user,
      tenant: TenancyDable.current_tenant,
      membership: TenancyDable.current_membership
    )
  end
end
```

```ruby
# app/policies/invoice_policy.rb
class InvoicePolicy < ApplicationPolicy
  def show?   = same_tenant? && member?    # all helpers are private; read role from the context
  def update? = same_tenant? && manager?
  def destroy? = same_tenant? && owner?

  class Scope < ApplicationPolicy::Scope
    # inherits the fail-closed tenant filter; override `resolve` (call `super`) to layer more
  end
end
```

`TenancyDable::Policy::Base` is **secure-by-default**: `index?/show?/create?/update?/destroy?` all return `false` until a subclass grants them (`new?`→`create?`, `edit?`→`update?`). The nested `Scope` **fails closed** — `policy_scope(Invoice)` returns `scope.none` when there's no active tenant, otherwise `scope.where(tenant_id: tenant.id)`.

The generated `ApplicationPolicy` (from `tenancy_dable:install`) ships a `Context = TenancyDable::Policy::Context` alias, because the `Context` constant lives in the enclosing `TenancyDable::Policy` module — not in `Base` — and so would not otherwise resolve through `ApplicationPolicy`. The alias lets policy specs build the subject as `ApplicationPolicy::Context.new(user:, tenant:, membership:)` (equivalently, `TenancyDable.pundit_context(...)`) without reaching into the gem's namespace.

## Opt-in: ActiveJob tenant propagation

A background job should run under the same workspace as the request that enqueued it. The `TenancyDable::Job` concern carries the current tenant's id **and the acting membership's id** through the serialized payload and restores both for `perform`, so a job's context (the workspace *and* the role within it) matches the enqueuing request's, not just the tenant. A membership of another tenant travels too, and reads in `perform` as `foreign_membership?`, not as `current_membership`.

It is **not** auto-required (so ActiveJob stays an optional dependency) — wire it up explicitly:

```ruby
require "tenancy_dable/job"   # in an initializer, or at the top of application_job.rb

class ApplicationJob < ActiveJob::Base
  include TenancyDable::Job
end
```

```ruby
TenancyDable.with_tenant(workspace) do
  ReportJob.perform_later      # captures workspace.id + current_membership.id at enqueue
end
# In the worker, `perform` runs inside TenancyDable.with_tenant(workspace) with current_membership
# restored — reads scope, bulk writes pass the guard, the role is known, exactly as inline.
```

Fail-open by design: a job enqueued with no current tenant performs untouched; if the tenant (or membership) was deleted before the job runs, that record reloads to nil — `perform` runs under `with_tenant(nil)` with a nil membership. **Backward compatible:** a payload enqueued before v0.3.0 carries no membership key, so it restores a nil membership; tenant propagation is byte-for-byte unchanged.

## Opt-in: Action Cable tenant resolution

A channel subscription should run under the same workspace as a request does. `TenancyDable::Channel` is the Cable parallel to [`resolve_tenant!`](#3-slug-resolution): it resolves the tenant **by slug** from the subscription params, enforces membership, and runs every channel action inside the tenant context — so a channel's reads scope and its bulk writes pass the guard exactly like a controller action's.

Like `Job`, it is **not** auto-required (so Action Cable stays an optional dependency) — wire it up explicitly:

```ruby
require "tenancy_dable/channel"   # in an initializer, or atop application_cable/channel.rb

class TenantChannel < ApplicationCable::Channel
  include TenancyDable::Channel

  def subscribed
    reject_unless_member!   # reject unless current_user is a member of the resolved tenant
    stream_for_tenant       # stream from "tenant:<id>" — never a cross-tenant stream name
  end

  # Every client-invoked action runs inside TenancyDable.with_tenant(current_tenant) with
  # current_membership set, so its reads are tenant-scoped automatically.
  def stats
    transmit(open: Invoice.where(state: "open").count)   # scoped to current_tenant
  end
end
```

**The gem does not own Cable authentication.** Connection-level user identification stays the host's job — your `ApplicationCable::Connection` must `identified_by :current_user` and establish it however you authenticate (cookie/session/token). Action Cable exposes `current_user` as a reader on the channel; the concern only *reads* it, never establishes it. That one line is the entire requirement — the gem ships no auth code.

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user   # authenticate however you like; the concern reads it
  end
end
```

The frozen helpers a channel inherits:

| Helper | What it does |
|---|---|
| `current_tenant` / `current_membership` | Memoized, **slug-resolved** tenant + the acting user's membership in it (or nil). |
| `tenant_member?` | Whether `current_user` is a member of `current_tenant`. |
| `reject_unless_member!` | Call in `#subscribed`: `reject` the subscription unless the user is a member. |
| `stream_for_tenant(suffix = nil)` | `stream_from "tenant:<id>"` (+ `":<suffix>"`) — tenant-namespaced, never cross-tenant. |
| `with_tenant_context(&blk)` | Run a block inside the resolved tenant context — for DB reads in `#subscribed`, where there is no auto-wrap. |

All are **safe when no tenant resolves** (slug absent or unknown): the membership is nil, so `reject_unless_member!` rejects the subscription (the secure outcome). Resolution is **slug-only** ([invariant 5](#security-invariants)) — it never trusts a tenant id from the params.

## Generating tenant-scoped models

```bash
bin/rails generate tenancy_dable:model Invoice number:string amount:integer
```

Like `rails g model`, but the generated class `include`s `TenancyDable::Scoped` + declares `belongs_to_tenant`, and the migration prepends the tenant foreign key (`tenant_id`) with its index and FK.

## Errors

Every error subclasses `TenancyDable::Error`, so a host can `rescue TenancyDable::Error` to trap any tenancy failure:

| Error | Raised when |
|---|---|
| `NoTenantError` | fail-closed: scoped query with `require_tenant` active and no current tenant |
| `TenantImmutableError` | reassigning a persisted record's tenant fk |
| `BulkWriteError` | guarded `update_all`/`delete_all`/`destroy_all` without a valid current-tenant scope |
| `CrossTenantError` | reserved for the cross-tenant `belongs_to` message style |
| `NotAMemberError` | the resolved acting user is not a member of the resolved tenant |
| `TenantNotFoundError` | reserved for host / non-bang `find_by` resolution strategies (the `:raise` path itself raises `ActiveRecord::RecordNotFound`) |
| `TenantOverrideError` | `current_tenant` reassigned to a different tenant while `audit_overrides == :raise` |
| `ConfigurationError` | invalid configuration |

## Security invariants

The boundary this gem owns, in one place (each is proven by a spec; see [DESIGN.md §11](DESIGN.md)):

1. **Fail-closed when configured** — `require_tenant` active + no tenant ⇒ raise, never a silent `all`.
2. **No cross-tenant read path** — filter by tenant before ordering; bulk-writes guarded; resolution enforces membership.
3. **`tenant_id` immutable** after create.
4. **Pundit scope fails closed** — `scope.none` with no active tenant.
5. **Slug-only resolution** — never trust a tenant id from the URL.
6. **No PII/secret leakage** — audit logs carry tenant ids only, never payloads.

## Development

```bash
bin/setup          # bundle install
bundle exec rake   # rspec + standard
bin/console        # IRB with the gem loaded
```

The test harness boots a real (tiny) Rails app via Combustion under `spec/internal/`, so the gem is exercised against genuine ActiveRecord + ActionPack rather than mocks.

## Versioning

`tenancy_dable` follows [Semantic Versioning](https://semver.org). Because it is the propagation mechanism for the edidable skeleton family, the [frozen public contract](DESIGN.md) defines what counts as a breaking change. See [UPGRADING.md](UPGRADING.md) for the semver policy, how to bump the gem across derived projects, and the guide for migrating an existing skeleton app onto the gem.

## License

[MIT](LICENSE.txt) © 2026 Lucas Guedes
