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
| **Row-scoping engine** | `belongs_to_tenant` scoping, **fail-closed when configured** (`require_tenant`), immutable `tenant_id`, a read guard and a bulk-write guard, a refusal to create into another tenant, declared tenancy with an audit, fiber-safe context, opt-in ActiveJob tenant propagation, and an optional **Postgres RLS** hook |
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
| `guard_reads` | `true` | Raise `CrossTenantReadError` on a scoped read pinned to another tenant or with its tenant filter removed. `false` restores the 0.4.0 read behaviour. |
| `isolation_check` | `:raise` | Under a fiber scheduler with thread isolation, a tenant write raises `UnsafeIsolationError` (`:raise`), logs (`:warn`) or is not checked (`:off`). |
| `require_bypass_reason` | `false` | When true, `without_tenant` without a non-blank `reason:` raises `BypassReasonError`. |
| `audit_allowed` | `{}` | Model name => reason, for reviewed models you do not own; `TenancyDable.audit` skips them. |
| `audit_ignored_namespaces` | `%w[ActiveStorage ActionText ActionMailbox SolidQueue SolidCache SolidCable]` | Namespaces `TenancyDable.audit` skips. Append with `+=`. |
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
- **Reads are guarded too** ([below](#the-read-guard)), and **writing into another tenant's rows is refused** ([below](#writing-into-another-tenants-rows-is-refused)).

Context helpers on the `TenancyDable` facade:

```ruby
TenancyDable.current_tenant            # => the active workspace (or nil)
TenancyDable.current_tenant = workspace
TenancyDable.with_tenant(workspace) { … }  # set for the block, restore after (nesting-safe; returns block value)
TenancyDable.without_tenant(reason: "nightly report") { … }  # disable scoping for the block; the reason is optional
TenancyDable.current_membership        # => the acting membership, or nil when it is not the current tenant's
TenancyDable.foreign_membership?       # => true when a membership is set but is not the current tenant's
```

#### The read guard

An association's relation (`other_tenant.widgets`) replaces the default scope's tenant filter with the owner's, so without a guard a read through it returns another tenant's rows while you act in yours. While a tenant is current, a read on a scoped model whose tenant filter points at a **different** tenant, or has been **removed**, raises `TenancyDable::CrossTenantReadError`:

```ruby
TenancyDable.with_tenant(b) do
  a.widgets.to_a                          # => raises CrossTenantReadError (also .count, .pluck, .exists?, a.widget_ids, a has_one)
  a.widgets.destroy_all                   # => raises; nothing is deleted
  Widget.where(tenant_id: a.id)           # .to_a raises; so does an IN list across tenants
  Widget.unscope(where: :tenant_id).to_a  # raises (also rewhere, merge, and an `or` with another tenant's relation)
  Widget.invert_where.to_a                # raises (so does unscoped.where.not(tenant_id: ...), a range, a subquery on the tenant column)
  b.widgets.to_a                          # fine: the current tenant
end

TenancyDable.with_tenant(a) { a.widgets.to_a }                                  # enter the tenant
TenancyDable.without_tenant(reason: "usage report") { Widget.where(tenant_id: [a.id, b.id]).count }  # or bypass on purpose
```

`config.guard_reads = false` turns it off. It never applies inside `without_tenant` or with no current tenant at the moment of the read (the default scope decides there). It also covers the less obvious shapes:

- a tenant predicate that is not an equality: `invert_where`, `where.not(tenant_id: ...)`, a range, or a subquery on the tenant column, including one brought in through `merge` or `unscoped`;
- a relation **built** with no tenant current (or inside `without_tenant`) and **loaded** inside a tenant: it is refused, unless it is pinned to the current tenant;
- `cache_key`, `cache_version` and `cache_key_with_version` on a refused relation, which read the other tenant's rows;
- a refused relation compiled into a subquery, `from` or `with` of another model. Side effect: `to_sql` and `arel` on a refused relation raise too.

`update_all(tenant_id: ...)` (a Hash with the tenant column among its keys) raises `TenancyDable::TenantImmutableError`, except inside `without_tenant`.

The guard targets the shapes Active Record produces on its own, and its **documented residuals** are explicit relation surgery:

- `Widget.unscoped` (and `unscoped { }`) with **no** tenant predicate, the Active Record bypass the guard must keep working. `Widget.unscoped.where(tenant_id: other.id)` is refused like any other pin;
- `except(:where)`, `only(...)`, and an `or` with an unscoped relation;
- SQL-string predicates, such as `where("tenant_id = ?", x)`, and SQL-string `update_all`;
- raw SQL: `find_by_sql`, `connection.select_all`;
- `reload` by id, and the cache key of an association that is already loaded (no query runs, so nothing is read that was not already in memory).

A global `validates :code, uniqueness: true` on a scoped model builds on `unscoped`, so it reveals whether another tenant holds a value. That is a host choice, not guarded; use `validates_uniqueness_to_tenant` to scope it.

#### Writing into another tenant's rows is refused

While a tenant is current, writing to another tenant's rows raises `TenancyDable::CrossTenantWriteError`, with or without validators and under `save(validate: false)`. That covers creating a scoped record with another tenant's id, and updating, destroying, touching, `update_columns` and `delete` of a record that belongs to another tenant (`valid?` on such a record raises as well). A blank tenant id on a new record still takes the current tenant, and an id equal to the current tenant is accepted.

```ruby
TenancyDable.with_tenant(b) do
  Widget.create!(tenant_id: a.id)   # => raises CrossTenantWriteError
  a_widget.update!(name: "x")       # => raises (a_widget belongs to tenant a)
  a.widgets.insert_all([{name: "x"}])  # => raises; so do upsert_all and insert_all!
end
TenancyDable.with_tenant(a) { Widget.create!(name: "ok") }  # enter the target tenant instead
TenancyDable.with_tenant(a_widget.tenant) { a_widget.update!(name: "x") }
```

`insert_all`, `insert_all!`, `upsert_all` and their singular forms are checked per row. An **upsert** is also refused when its conflict target does not include the tenant column, because it could overwrite another tenant's row: that includes the primary key and, on an adapter without conflict targets such as MySQL, every upsert on a scoped model inside a tenant. The fix is a unique index that includes the tenant column (and `unique_by:` naming it), `with_tenant(record.tenant) { ... }`, or `without_tenant(reason: "...") { ... }`.

`update_columns(tenant_id: ...)` and `update_column(:tenant_id, ...)` with a different id raise `TenantImmutableError`, like the writer.

#### Declaring tenancy and auditing it

Every model is tenant-scoped or global, and the gem makes you say which. `belongs_to_tenant` declares a model scoped; `tenant_global` (available on every Active Record class) declares one global, with a reason. A model declares once; a subclass inherits, and a second declaration raises `ConfigurationError`.

```ruby
class Country < ApplicationRecord
  tenant_global because: "reference data shared by every tenant"
end

class Invoice < ApplicationRecord
  include TenancyDable::Scoped
  belongs_to_tenant tag: :billing   # tag: is free-form
end
```

`tenant_global` also takes `tag:` and `allow_tenant_fk: true` (for a deliberately unscoped table that carries the tenant column). `TenantModel`, `UserModel` and `MembershipModel` declare themselves. `TenancyDable.audit` then proves nothing was forgotten:

```ruby
expect(TenancyDable.audit).to be_empty   # in a spec
```

```bash
bin/rails tenancy_dable:audit            # in CI: one finding per line on stderr, exit 1 on findings
```

Findings are `:undeclared` (no declaration), `:global_with_tenant_fk` (declared global but has the tenant column) and `:scoped_without_index` (no index leads with the tenant column); each responds to `model`, `kind` and `message`. A global model that shares a scoped model's table is reported as `:global_with_tenant_fk` even with `allow_tenant_fk: true`. Abstract classes, real STI subclasses (same table as the base class) and the namespaces in `audit_ignored_namespaces` are skipped, and `audit_allowed` records a reviewed model you do not own.

#### Fiber safety

`Current` is isolated per thread by default. Under a fiber scheduler (a fiber-per-request server, anything on `async`) every fiber on a thread would share it, so a tenant-state write there raises `TenancyDable::UnsafeIsolationError` until you set `config.active_support.isolation_level = :fiber` (`config.isolation_check = :warn` or `:off` relaxes it). Puma, Sidekiq and rake never run a scheduler, so they are unaffected, unless your own code opens an `Async { }` or `Sync { }` reactor inside them: that sets the scheduler for the thread and the check fires under thread isolation.

Work handed to another thread or fiber starts with no tenant. With `require_tenant` on, a scoped read there raises (fail closed). With it **off** (the default), a thread or fiber that lost the context reads **every** tenant, which is the fail-open default. A host that spawns threads or uses fibers should set `require_tenant = true` and carry the context across on purpose:

```ruby
Thread.new(&TenancyDable.carry { Report.build })      # carry returns a lambda that runs the block in the context taken NOW

snapshot = TenancyDable.snapshot                      # tenant, membership and the without_tenant flag
executor.post { snapshot.restore { Report.build } }   # restored for the block, then put back
```

#### Auditing `without_tenant`

`without_tenant` takes an optional `reason:`. When something subscribes to `"without_tenant.tenancy_dable"`, each call publishes `reason`, `tenant_id` and `call_site` (an absolute path, `"/srv/app/app/jobs/sweep.rb:12"`), never a record:

```ruby
ActiveSupport::Notifications.subscribe(TenancyDable::WITHOUT_TENANT_EVENT) do |*, payload|
  Rails.logger.info("tenant bypass: #{payload[:reason]} at #{payload[:call_site]}")
end
```

`config.require_bypass_reason = true` makes a call without a reason raise `BypassReasonError`. `reason:` accepts only `nil`, a String or a Symbol; anything else raises `BypassReasonError`, so a record can never reach the event payload.

Write tenant state only through the facade (`TenancyDable.current_tenant=`, `with_tenant`, `without_tenant`): `Current.set` and `Current.tenant=` skip the isolation check, the audit and the RLS hook.

#### Localizing messages

The gem's three validation messages are I18n keys under `errors.messages`: `cross_tenant`, `last_owner` and `slug_format`. It ships `en` and `pt-BR`. `en` always loads; `pt-BR` loads only when the host declares it in `config.i18n.default_locale` or `config.i18n.available_locales` in `config/application.rb` (not in an initializer, which runs too late), so an English-only host's `I18n.available_locales` does not gain `pt-BR`. The host's own locale files win over the gem's for the same key. For any other locale, translate the keys, or enable fallbacks that reach `:en` (`config.i18n.fallbacks = [:en]`; plain `fallbacks = true` falls back to your default locale only), or override them at any level of Active Model's lookup:

```yaml
es:
  errors:
    messages:
      cross_tenant: "pertenece a otro inquilino"
      last_owner: "no se puede cambiar: debe quedar al menos un propietario"
      slug_format: "solo minúsculas, números y guiones simples"
```

`errors.details` carries the symbols (`:cross_tenant`, `:last_owner`). Exception messages stay English.

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

Fail-open by design: a job enqueued with no current tenant performs untouched. If the tenant was deleted before the job runs, `perform` raises `TenancyDable::TenantNotFoundError` instead of running with no tenant (a host can `discard_on TenancyDable::TenantNotFoundError`); a deleted membership reloads to nil. **Backward compatible:** a payload enqueued before v0.3.0 carries no membership key, so it restores a nil membership; tenant propagation is byte-for-byte unchanged.

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
| `TenantImmutableError` | reassigning a persisted record's tenant fk (writer, `update_columns`, or `update_all` with the fk among its keys) |
| `BulkWriteError` | guarded `update_all`/`delete_all`/`destroy_all` without a valid current-tenant scope |
| `CrossTenantError` | reserved for the cross-tenant `belongs_to` message style (its `MESSAGE` equals the `en` default of `cross_tenant`) |
| `NotAMemberError` | the resolved acting user is not a member of the resolved tenant |
| `TenantNotFoundError` | a `TenancyDable::Job` whose enqueue-time tenant no longer resolves (also reserved for host / non-bang `find_by` resolution strategies; the `:raise` path itself raises `ActiveRecord::RecordNotFound`) |
| `TenantOverrideError` | `current_tenant` reassigned to a different tenant while `audit_overrides == :raise` |
| `CrossTenantReadError` | a scoped read pinned to another tenant, or with its tenant filter removed, while a tenant is current |
| `CrossTenantWriteError` | creating, updating, destroying, touching or deleting another tenant's record, or an `insert_all` / upsert that could reach one, while a tenant is current |
| `UnsafeIsolationError` | tenant state written under a fiber scheduler with thread isolation (`isolation_check == :raise`) |
| `BypassReasonError` | `without_tenant` without a reason while `require_bypass_reason` is on |
| `ConfigurationError` | invalid configuration, or an invalid or repeated tenancy declaration |

## Security invariants

The boundary this gem owns, in one place (each is proven by a spec; see [DESIGN.md §11](DESIGN.md)):

1. **Fail-closed when configured** — `require_tenant` active + no tenant ⇒ raise, never a silent `all`.
2. **No cross-tenant read path** — filter by tenant before ordering; a read pinned to another tenant, or with its filter removed, raises; bulk writes guarded; a write into another tenant's rows raises; resolution enforces membership (within the [documented residuals](#the-read-guard)).
3. **`tenant_id` immutable** after create.
4. **Pundit scope fails closed** — `scope.none` with no active tenant.
5. **Slug-only resolution** — never trust a tenant id from the URL.
6. **No PII/secret leakage** — audit logs and the `without_tenant` event carry tenant ids (and the host's reason), never payloads.
7. **No shared tenant state across fibers** — under a fiber scheduler with thread isolation, a tenant write raises.

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
