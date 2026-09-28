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

Read this gem's [CHANGELOG.md](CHANGELOG.md) before a MINOR/MAJOR bump. The install
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

---

## See also

- [README.md](README.md) — install, configuration reference, the four layers.
- [DESIGN.md](DESIGN.md) — the frozen public contract, load graph, and the six security invariants with their proving specs.
- [CHANGELOG.md](CHANGELOG.md) — what changed in each release; read before a MINOR/MAJOR bump.
