# Upgrading & Adopting TenancyDable

`tenancy_dable` is the **standards-propagation layer** for the edidable Rails SaaS
skeleton family. The whole point of shipping the tenancy stack as a gem is that a
fix or hardening lands **once**, here, and every derived project picks it up with a
`bundle update` — instead of N hand-synced copies drifting apart.

This guide covers three things:

1. [How a derived edidable project consumes the gem](#1-consuming-the-gem) — both a **new project** and the wiring it expects.
2. [The versioning policy and how to bump the gem across projects](#2-versioning--bumping-across-projects).
3. [Migrating an **existing** skeleton app](#3-migrating-an-existing-skeleton-app) off the in-house `Tenantable` / `SetCurrentTenant` / `ApplicationPolicy` and onto the gem.

For the install steps and per-layer API, see [README.md](README.md). For the frozen
public contract and security invariants, see [DESIGN.md](DESIGN.md).

---

## 1. Consuming the gem

### New project (bootstrapped from the skeleton)

```ruby
# Gemfile
gem "tenancy_dable", "~> 0.1.0"
```

```bash
bundle install
bin/rails generate tenancy_dable:install
bin/rails db:migrate
```

Then finish the wiring the generator printed (it does **not** edit your existing
models — see [what `tenancy_dable:install` creates](README.md#what-tenancy_dableinstall-creates)):

```ruby
class Tenant < ApplicationRecord
  include TenancyDable::TenantModel
end

class User < ApplicationRecord
  include TenancyDable::UserModel
end

class Membership < ApplicationRecord
  include TenancyDable::MembershipModel
  # never `include TenancyDable::Scoped` — Membership is queried before a tenant is known
end
```

Point resolution at your auth layer (the gem is auth-agnostic) and wire Pundit:

```ruby
# config/initializers/tenancy_dable.rb
config.current_user_resolver = -> { current_user }   # e.g. Devise; default reads Current.user

# app/controllers/application_controller.rb
include Pundit::Authorization
resolve_tenant!

def pundit_user
  TenancyDable.pundit_context(
    user: Current.user,
    tenant: TenancyDable.current_tenant,
    membership: TenancyDable.current_membership
  )
end
```

That's the whole adoption for a greenfield project. Generate tenant-scoped models
with `bin/rails g tenancy_dable:model NAME field:type`.

---

## 2. Versioning & bumping across projects

### Semver against the frozen contract

`tenancy_dable` follows [Semantic Versioning](https://semver.org). The **frozen
public contract** in [DESIGN.md](DESIGN.md) (and `.midgal/PLAN.md`) is the surface
semver is measured against — names, signatures, file paths, config defaults, error
classes, and the documented isolation semantics.

| Bump | Means | Examples | Safe to `bundle update`? |
|---|---|---|---|
| **MAJOR** (`1.0.0` → `2.0.0`) | A change to the frozen public surface or to isolation semantics. | Remove/rename a config setting or error class; change a public signature (`belongs_to_tenant`, `resolve_tenant!`, `pundit_context`, `with_tenant`); flip a default that changes isolation (e.g. fail-open → fail-closed); change the default-scope decision tree. | **No** — read [UPGRADING](UPGRADING.md) notes for that release first. |
| **MINOR** (`1.1.0` → `1.2.0`) | Backward-compatible additions. | A new config setting with a safe default; a new `TenancyDable::Error` subclass; a new policy/relation helper; a new generator option; the opt-in `TenancyDable::Job` seam. | **Yes** (post-1.0). |
| **PATCH** (`1.1.0` → `1.1.1`) | Bug or **security** fix, no surface change. | Close a cross-tenant leak; correct a default-scope edge case; tighten the bulk-write guard. | **Yes, and promptly** — this is the path security fixes ship on. |

> **Security fixes propagate as PATCH** (or MINOR if they must add surface). Because
> the row-scoping core is the security boundary for every derived app, treat a
> `tenancy_dable` patch bump as something to pick up quickly, not "someday."

### Pre-1.0 caveat

While the gem is `0.x`, **a `0.MINOR.0` bump may carry breaking changes** (semver
§4 lets `0.x` move fast before the surface stabilizes). So pin conservatively until
`1.0`:

```ruby
gem "tenancy_dable", "~> 0.1.0"   # auto-accept 0.1.x patches; review 0.2.0 by hand
```

After `1.0`, `~> 1.0` is safe for routine updates (accepts every backward-compatible
`1.x`, locks the major).

### Bumping a single project

```bash
bundle update tenancy_dable
bin/rails generate tenancy_dable:install   # idempotent — re-run to pick up NEW templates; existing files are skipped
bin/rails db:migrate                       # if the bump shipped new migrations
bundle exec rspec                          # your app's suite is the acceptance gate
```

Read this gem's [CHANGELOG.md](CHANGELOG.md) before a MINOR/MAJOR bump. Bumping
from 0.4.0 to 0.5.0 changes behavior on purpose (reads, writes and the isolation
check now raise where they used to leak): read [Upgrading to v0.5.0](#upgrading-to-v050)
first, it lives under §3 below. The install
generator never overwrites a host-edited file, so re-running it only *adds* anything
new a release introduced.

### Bumping the whole edidable family

Because every derived project depends on the same gem, propagation is a fan-out of
the single-project bump:

1. Release the fix here, tagged (e.g. `v0.1.1`), CHANGELOG updated.
2. In each derived project: `bundle update tenancy_dable` → migrate → run tests → ship.
3. For a security PATCH, do this across all projects on the same day; the CHANGELOG
   entry tells you the blast radius.

---

## 3. Migrating an existing skeleton app

If your app predates the gem, it carries the tenancy stack as **in-house** code —
conventionally a `Tenantable` model concern, a `SetCurrentTenant` controller
concern, and a hand-written `ApplicationPolicy`. Migrating means swapping each
in-house piece for its gem equivalent. Your **data and tables do not change** — the
gem expects the same `tenants(slug)` / `memberships(user_id, tenant_id, role)`
shape the skeleton already has.

### The mapping

| In-house (delete / replace) | Gem replacement (include / keep) |
|---|---|
| `app/models/concerns/tenantable.rb` (row-scoping, `default_scope`, `current_tenant` assignment) | `include TenancyDable::Scoped` + `belongs_to_tenant` in each scoped model |
| In-house `Current.tenant` / `with_tenant` / `without_tenant` helpers | The `TenancyDable` facade: `current_tenant`, `with_tenant`, `without_tenant` |
| `app/controllers/concerns/set_current_tenant.rb` (before_action resolving the tenant) | `include`d on `ActionController::Base` by the railtie; call `resolve_tenant!` |
| In-house tenant-from-subdomain/id lookup | `resolve_tenant!` — **slug only**, `find_by!(slug:)`, never an id from the URL |
| Hand-written `ApplicationPolicy` base body | `ApplicationPolicy < TenancyDable::Policy::Base` (from the install generator) |
| In-house `Membership` role predicates / role constants | Generated from `config.roles` by `TenancyDable::MembershipModel` (`owner?`, `admin?`, …) |
| Manual "is this user in this workspace?" checks | `user.member_of?(tenant)` / `user.membership_for(tenant)` |

### Step by step

**1. Add the gem and run the generator.**

```ruby
gem "tenancy_dable", "~> 0.1.0"
```

```bash
bundle install
bin/rails generate tenancy_dable:install
```

The generator **skips** files you already have (initializer, migrations, `Current`,
routes), so on an existing app it mostly drops in `config/initializers/tenancy_dable.rb`
and `app/policies/application_policy.rb` and prints the include reminders. **Skip the
migrations if your `tenants`/`memberships` tables already exist** — delete the
generated migration files rather than running them.

**2. Configure to match what the in-house code assumed.** Open the initializer and
set `roles`, `manager_roles`, `tenant_fk`, and `slug_param` to whatever your
`Tenantable`/`SetCurrentTenant` used. If your auth isn't `Current.user`-based, set
`current_user_resolver` (e.g. `-> { current_user }`).

**3. Swap the model concern.** In every model that was `include Tenantable`:

```ruby
# before
class Invoice < ApplicationRecord
  include Tenantable
end

# after
class Invoice < ApplicationRecord
  include TenancyDable::Scoped
  belongs_to_tenant
  # move any in-house per-tenant uniqueness onto validates_uniqueness_to_tenant
end
```

Then **delete `app/models/concerns/tenantable.rb`.**

**4. Mix in the identity concerns** on `Tenant`, `User`, `Membership` (see §1). If
you had in-house role predicates or a last-owner guard, delete them — the gem
generates the predicates from `config.roles` and ships the last-owner guard. **Do
not** add `Scoped` to `Membership`.

**5. Swap the controller concern.** Replace `include SetCurrentTenant` (and its
`before_action`) with `resolve_tenant!`. The railtie already mixes
`TenancyDable::Controller::Resolvable` into `ActionController::Base`, so you only
call the macro:

```ruby
# before
class ApplicationController < ActionController::Base
  include SetCurrentTenant
  before_action :set_current_tenant
end

# after
class ApplicationController < ActionController::Base
  resolve_tenant!
end
```

Then **delete `app/controllers/concerns/set_current_tenant.rb`.** Make sure tenant
routes are nested under `scope "/:tenant_slug"` (the generator injects a commented
scaffold). If your in-house resolver used a subdomain or an id, switch the routes to
the slug — slug-only is a security invariant, not a preference.

**Decide how non-members are handled.** Resolution refuses a user who isn't a member
of the resolved workspace **before** your action runs. By default it raises
`TenancyDable::NotAMemberError`; pick the failure shape that fits the app via
`config.on_not_a_member`:

- **Reuse an existing Pundit rescue.** If your controllers already
  `rescue_from Pundit::NotAuthorizedError` (the edidable skeleton does), set
  `config.on_not_a_member = :not_authorized` and non-members flow through that **same**
  handler — no bespoke `rescue_from` for tenancy.
- **Rescue the tenancy error directly.** Otherwise add a clause for it, e.g.

  ```ruby
  rescue_from TenancyDable::NotAMemberError do
    redirect_to workspaces_path, alert: "You're not a member of that workspace."
  end
  ```

  A callable (`config.on_not_a_member = ->(tenant) { head :forbidden }`) gives the
  same control inline, run in the controller with the resolved tenant as its argument.

The built-in messages are **English** (`"acting user is not a member of tenant …"`).
If you surface them to users, **localize in your rescue** rather than relying on the
raised string.

**6. Rebase your policies.** Keep your concrete policies (`InvoicePolicy`, etc.) —
just make sure they descend from the new `ApplicationPolicy < TenancyDable::Policy::Base`
and use the gem's private helpers (`same_tenant?`, `owner?`, `manager?`, `member?`)
instead of in-house ones. Feed Pundit the context via `pundit_user` (see §1). Replace
any in-house `policy_scope` base with `ApplicationPolicy::Scope` (it fails closed).

Keep the `Context = TenancyDable::Policy::Context` alias the generator now writes
into `ApplicationPolicy`. The `Context` constant lives in the enclosing
`TenancyDable::Policy` module, **not** in `Base`, so without the alias it would not
resolve through `ApplicationPolicy` — existing policy specs that build the subject as
`ApplicationPolicy::Context.new(user:, tenant:, membership:)` keep working **because**
of it. Build `pundit_user` with `TenancyDable.pundit_context(user:, tenant:, membership:)`
(see §1); the two construct the same context triple.

**7. (Optional) Background jobs.** If you propagated the tenant into jobs by hand,
delete that and opt into the gem's seam:

```ruby
require "tenancy_dable/job"
class ApplicationJob < ActiveJob::Base
  include TenancyDable::Job
end
```

As of v0.3.0 the seam also carries the acting **membership** (not just the tenant),
so `current_membership` inside `perform` matches the enqueuing request's — delete any
hand-rolled role-threading too. It is backward compatible: a payload enqueued before
v0.3.0 simply restores a nil membership.

**8. (Optional) Action Cable channels.** If you run channels, opt into
`TenancyDable::Channel` — the Cable parallel to `resolve_tenant!`. It resolves the
tenant by slug per subscription, enforces membership, and runs each channel action
inside the tenant context:

```ruby
require "tenancy_dable/channel"   # opt-in, like Job — Action Cable stays optional

class TenantChannel < ApplicationCable::Channel
  include TenancyDable::Channel
  def subscribed
    reject_unless_member!   # reject a non-member (or an unknown/absent slug)
    stream_for_tenant       # "tenant:<id>" — tenant-namespaced, never cross-tenant
  end
end
```

**The gem does not own Cable connection auth** (the same guardrail as the rest of the
stack: it never touches your authentication). Connection-level user identification
stays your job — your `ApplicationCable::Connection` must `identified_by :current_user`
(establish it however you authenticate). The concern only *reads* `current_user` off
the connection. That one line is the whole requirement; the gem ships no auth code.

**9. Run your suite.** Your app's tests are the acceptance gate. Pay attention to
the behavior differences below.

### What stays untouched

- Your `tenants` / `memberships` / `users` **tables and data** (same schema the gem expects).
- Your `Tenant` / `User` / `Membership` **models** — they keep their app-specific code; you only swap which concern they include.
- Your **concrete policies** and **routes** (modulo the slug switch).
- Your **authentication** stack — the gem never touches it; it only *reads* the acting user via `current_user_resolver`.
- Your **`Current` attributes** model (keep it; ensure it has `attribute :user`).

### Behavior differences to expect

- **Default is fail-OPEN.** Unlike some in-house concerns that raised on a missing
  tenant, the gem's default scope returns `all` when no tenant is set **unless** you
  set `require_tenant` (boolean or per-query callable). Set it to keep the old
  fail-closed behavior in jobs/consoles/rake tasks.
- **`tenant_id` is immutable after create.** Code that reassigned a record's tenant
  now raises `TenantImmutableError`. This is intended; fix the call site.
- **Bulk writes are guarded.** `update_all`/`delete_all`/`destroy_all` on a scoped
  model with no active tenant now raise `BulkWriteError`. Wrap deliberate
  cross-tenant sweeps in `TenancyDable.without_tenant { … }`.
- **Resolution is slug-only and membership-enforced.** A non-member hitting a
  workspace URL gets `NotAMemberError` *before* the action runs (or
  `Pundit::NotAuthorizedError` / your callable's outcome — see `on_not_a_member` in
  step 5); an unknown slug raises `ActiveRecord::RecordNotFound` (or returns a null
  tenant with `on_tenant_not_found = :null`).
- **Jobs now restore the membership too (v0.3.0).** `TenancyDable::Job` previously
  left `current_membership` nil inside `perform` (it carried only the tenant); it now
  restores the enqueue-time membership as well. A job that read `current_membership`
  and relied on it being nil should be reviewed. Backward compatible the other way:
  payloads enqueued before v0.3.0 (no membership key) restore a nil membership.
- **`current_membership` is nil outside its own tenant (v0.4.0).** Inside
  `with_tenant(other_tenant)`, or after assigning `current_tenant` directly, it used
  to return the outer tenant's membership; it now returns nil until the tenant is
  restored. If your code treats a nil `current_membership` as a system context,
  also check `TenancyDable.foreign_membership?`, or a job carrying a membership of
  another tenant starts to look like the system.
- **A role literally named `manager` is a foot-gun.** The membership generates a
  `manager?` predicate from `config.roles` (role == `"manager"`), while
  `Membership#manager?` / the policy `manager?` mean "role ∈ `manager_roles`." If
  you configure a role called `manager`, those two senses collide — pick a different
  role name.

### Upgrading to v0.5.0

v0.5.0 is a `0.MINOR` bump that turns three leaks into refusals. Run your suite
after `bundle update`: anything below that raises was reading or writing across
tenants and getting either nothing or another tenant's rows.

**Reads pinned to another tenant raise `CrossTenantReadError`.** While a tenant is
current, a read on a scoped model whose tenant filter points at a different tenant,
or has been removed, is refused. That covers:

- `Widget.where(tenant_id: other.id)` and `Widget.where(tenant_id: [a.id, b.id])`
  (an `IN` list is a multi-tenant read, even when it contains the current tenant);
- a read through another tenant's association, such as `other.widgets.to_a`,
  `.count`, `.pluck`, `.exists?`, `other.widget_ids`, or a `has_one`;
- a preload across tenants: `Tenant.where(id: [a.id, b.id]).includes(:widgets)`;
- `rewhere(tenant_id: other.id)`, `merge` with an unscoped relation,
  `unscope(where: :tenant_id)` (also the table-keyed form
  `unscope(where: {widgets: :tenant_id})`) and an `or` that mixes the tenant
  predicate in;
- a tenant predicate that is not an equality: `invert_where`,
  `where.not(tenant_id: ...)`, a range, or a subquery on the tenant column, also
  when it arrives through `merge` or `unscoped`;
- a relation **built** with no tenant current (or inside `without_tenant`) and
  **loaded** inside a tenant, unless it is pinned to the current tenant;
- `cache_key`, `cache_version` and `cache_key_with_version` of a refused relation,
  and a refused relation used as a subquery, `from` or `with` of another model.
  As a consequence `to_sql` and `arel` on a refused relation raise too;
- `other.widgets.destroy_all`, and destroying another tenant whose `dependent:`
  associations must be loaded.

Fix each call site by entering the tenant, or, when crossing is the point, by
bypassing on purpose:

```ruby
TenancyDable.with_tenant(other) { Widget.count }

TenancyDable.without_tenant(reason: "nightly usage report") do
  Widget.where(tenant_id: [a.id, b.id]).group(:tenant_id).count
end
```

Escape hatch: `config.guard_reads = false` restores the 0.4.0 read behaviour
across the app. The guard does nothing inside `without_tenant`, or when no tenant
is current at the moment of the read.

Documented residuals (see the README): `Model.unscoped` with **no** tenant
predicate passes, but `Model.unscoped.where(tenant_id: other.id)` is refused like
any other pin; `except(:where)`, `only(...)`, an `or` with an unscoped relation,
SQL-string predicates, raw SQL, `reload` by id, and the cache key of an association
that is already loaded.

**`update_all(tenant_id: ...)` raises `TenantImmutableError`**, like the
`tenant_id=` writer, except inside `without_tenant`. `update_columns(tenant_id: ...)`
and `update_column` with a different id raise it too. A SQL-string `update_all`
is a residual.

**Writing into another tenant raises `CrossTenantWriteError`.** Inside
`with_tenant(b)`, `Widget.create!(tenant_id: a.id)`, `Widget.create!(tenant: a)`,
`a.widgets.create!` and `save(validate: false)` with another tenant's id used to
persist a row in tenant A. They raise now, whatever validators the model has. So
does changing a record that already belongs to another tenant: `update`, `destroy`,
`touch`, `update_columns` and `delete` (and `valid?` on it), where 0.4.0 persisted
the change or, for a model with `validates_uniqueness_to_tenant`, failed in a
validator. `insert_all`, `insert_all!` and `upsert_all` are refused when a row
names another tenant, or when it goes through another tenant's relation
(`a.widgets.insert_all`). An **upsert** is also refused when its conflict target
does not include the tenant column, because it could overwrite another tenant's
row: that covers the primary key and, on an adapter without conflict targets such
as MySQL, every upsert on a scoped model inside a tenant. There is no setting for
this one. The fix is `with_tenant(record.tenant) { write }`, a unique index that
includes the tenant column (named in `unique_by:`), or
`without_tenant(reason: "...") { write }`.

This reaches **host test suites** that build other-tenant fixtures while a tenant
is current (a `before` block that enters tenant A and then calls
`create(:widget, tenant: other)`). Build those records inside their own tenant, or
in the example before entering one:

```ruby
other_widget = TenancyDable.with_tenant(other) { create(:widget) }
```

A new record with a blank tenant id still takes the current tenant, and an explicit
id equal to the current tenant is accepted, as before.

**The isolation check raises under a fiber scheduler (`UnsafeIsolationError`).**
Rails keeps `Current` per thread by default. Under a fiber scheduler (a
fiber-per-request server, anything on `async`) every fiber on the thread would share
one tenant, so a request could read the tenant another request wrote. The first
tenant write under a scheduler with `isolation_level = :thread` now raises. Fix the
cause:

```ruby
# config/application.rb
config.active_support.isolation_level = :fiber
```

Escape hatch while you migrate: `config.isolation_check = :warn` (logs every
detected write and carries on) or `:off`. Puma, Sidekiq and rake never have a
scheduler, so they are unaffected, unless your own code opens an `Async { }` or
`Sync { }` reactor inside them: the check fires there under thread isolation. To
run work on another thread with the tenant, use `TenancyDable.carry { ... }` or
`TenancyDable.snapshot` (README).

With `require_tenant` off (the default), a thread or fiber that lost the context
reads every tenant: that is the fail-open default. A host that spawns threads or
uses fibers should set `require_tenant = true` and `carry` the context. Write
tenant state only through the facade (`current_tenant=`, `with_tenant`,
`without_tenant`): `Current.set` and `Current.tenant=` skip the isolation check, the
audit and the RLS hook.

**`TenancyDable::Job` raises when its tenant is gone.** A job enqueued in a tenant
that was deleted before it runs now raises `TenancyDable::TenantNotFoundError`; in
0.4.0 it ran under no tenant. A job enqueued outside any tenant is unchanged. Add
`discard_on TenancyDable::TenantNotFoundError` to `ApplicationJob` if dropping it is
the right outcome.

**`without_tenant(reason:)` takes only `nil`, a String or a Symbol**; anything else
raises `BypassReasonError`. The event's `call_site` is an absolute path.

**A second tenancy declaration raises `ConfigurationError`.** `belongs_to_tenant`
and `tenant_global` each declare a model's tenancy once, and a subclass inherits its
parent's declaration. A model that calls both, calls either twice, or re-declares
below a declared parent fails at class load. `TenantModel`, `UserModel` and
`MembershipModel` now declare themselves `tenant_global`, so a host model that
includes one of them must not declare again.

**Validation messages are I18n keys.** The cross-tenant `belongs_to` error, the
last-owner error and the slug-format error moved from literal English strings to the
keys `cross_tenant`, `last_owner` and `slug_format` under `errors.messages`. The gem
ships `en` and `pt-BR`. In `en` nothing visible changes. In any other locale,
translate the three keys in your own locale file, or enable fallbacks that reach
`:en` (`config.i18n.fallbacks = [:en]`; plain `fallbacks = true` falls back to
your default locale only, which is not `:en` for most such hosts); otherwise Rails
shows its "translation missing" text where 0.4.0 showed English. Any key can be
overridden at any level of Active Model's lookup
(`activerecord.errors.models.<model>.attributes.<attribute>.<key>` and so on).

Three host-visible details:

- **Your locale files win.** A host file defining the same key overrides the gem's.
- **`pt-BR` loads only when the host declares it**, in `config.i18n.default_locale`
  or `config.i18n.available_locales` in `config/application.rb` (an initializer runs
  too late to be seen). An English-only host's `I18n.available_locales` does not
  gain `pt-BR`.
- **A `pt-BR` host now sees Portuguese** where 0.4.0 showed English for the
  last-owner, slug-format and cross-tenant messages (those were literal English in
  0.4.0 whatever the locale). A page, or a spec that asserts the English text,
  changes.

`errors.details` also changed: it carries the symbols `:cross_tenant` and
`:last_owner` instead of the English String (the slug-format error keeps `:invalid`).
Code that compared `details` to the old string, or a spec that does
(`errors.added?(:parent, "belongs to a different tenant")` still works in `en`),
needs the symbol. Exception messages stay English.

### Adopting declarations and the audit

New in v0.5.0 and **opt-in to run**: nothing raises at boot unless a model declares
twice or calls `tenant_global` wrongly, and the audit only runs when you call it. Every model is either tenant-scoped or global, and "global
because we forgot" is the failure the audit exists to catch.

1. Declare every model that is not scoped, with a reason:

   ```ruby
   class Country < ApplicationRecord
     tenant_global because: "reference data shared by every tenant"
   end
   ```

   Scoped models keep `belongs_to_tenant` (optionally `tag: :billing`). A global
   table that deliberately carries the tenant column (a record looked up before a
   tenant is current) passes `allow_tenant_fk: true`.
2. Run the audit in your suite, and in CI:

   ```ruby
   it "declares the tenancy of every model" do
     expect(TenancyDable.audit).to be_empty
   end
   ```

   ```bash
   bin/rails tenancy_dable:audit   # exits 1, one finding per line, on stderr
   ```

3. Triage the findings. `:undeclared` wants a declaration. `:global_with_tenant_fk`
   means a global model has a tenant column: scope it, or pass `allow_tenant_fk:
   true`. `:scoped_without_index` wants an index that leads with the tenant column.
4. Models you do not own (a library's, inheriting `ActiveRecord::Base`) go in
   configuration with the reason in one place; whole engines go in the namespace list.

   ```ruby
   config.audit_allowed = {"SomeGem::Record" => "reviewed: holds no tenant data"}
   config.audit_ignored_namespaces += %w[SomeEngine]
   ```

   Active Storage, Action Text, Action Mailbox and the Solid* tables are ignored by
   default.

A global model that shares a scoped model's table is reported as
`:global_with_tenant_fk` even with `allow_tenant_fk: true`, and only real STI
subclasses (same table as their base class) are skipped.

**Name collisions.** The gem adds the class methods `tenant_global`,
`tenancy_declaration`, `tenancy_global_reason` and `tenancy_tag` to every Active
Record class. A host macro of the same name on `ApplicationRecord` (an in-house
`tenant_global`, say) shadows the gem's, and the identity concerns' own
`tenant_global because:` would then call the host's. Retire the host macro, or
rename it, when you adopt the gem's.

To make `without_tenant` accountable, set `config.require_bypass_reason = true` and
add a `reason:` to each call; subscribe to `"without_tenant.tenancy_dable"` to log
where bypasses begin (README).

---

## See also

- [README.md](README.md) — install, configuration reference, the four layers.
- [DESIGN.md](DESIGN.md) — the frozen public contract, load graph, and the six security invariants with their proving specs.
- [CHANGELOG.md](CHANGELOG.md) — what changed in each release; read before a MINOR/MAJOR bump.
