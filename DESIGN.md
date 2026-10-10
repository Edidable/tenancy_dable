# TenancyDable — DESIGN (worker-facing contract)

> **Status: frozen.** This document expands `.midgal/PLAN.md` (the authoritative
> contract) into the per-symbol, per-file design that **every later phase
> implements verbatim**. Phase 00 writes no production code. If a phase must
> deviate, it records the reason in the [Deviations](#10-deviations--observations)
> section below and **keeps the public surface unchanged**.
>
> **v0.2.0 (nits run):** three additive fixes amend this contract — see §13. The
> v0.1.0 surface above stays frozen except as noted there.
>
> **v0.4.0:** `current_membership` answers only inside its own tenant, and
> `foreign_membership?` is added. See §15.
>
> **v0.5.0:** a read guard, refused creates into another tenant, declared
> tenancy with an audit, fiber safety, an audited `without_tenant`, and
> localizable validation messages. See §16, which amends §1, §3, §4, §5, §7, §8
> and §11; where an earlier section disagrees with §16, §16 wins.
>
> Read order for every downstream worker: `.midgal/PLAN.md` → `DESIGN.md` →
> your phase spec under `.midgal/phases/`.

---

## 1. Symbol inventory (index)

Every symbol named in the PLAN contract, the file it lives in, and the phase
that implements it. **Names here match `PLAN.md` exactly.**

| Symbol | File | Implemented in |
|---|---|---|
| `TenancyDable` (module + facade) | `lib/tenancy_dable.rb` | 02 (entry stub exists) |
| `TenancyDable::VERSION` | `lib/tenancy_dable/version.rb` | exists (`"0.0.1"` → `0.1.0` in 15; → `0.2.0` in nits phase 04, §13) |
| `TenancyDable::Configuration` | `lib/tenancy_dable/configuration.rb` | 02 (stub exists) |
| `TenancyDable::Current` | `lib/tenancy_dable/current.rb` | 02 |
| `TenancyDable::Error` + 8 subclasses | `lib/tenancy_dable/errors.rb` | 02 (`Error` base exists in entry) |
| `TenancyDable::Railtie` | `lib/tenancy_dable/railtie.rb` | 02 |
| `TenancyDable::Scoped` | `lib/tenancy_dable/scoped.rb` | 03 |
| `TenancyDable::RelationExtension` | `lib/tenancy_dable/relation_extension.rb` | 03 |
| `TenancyDable::TenantModel` | `lib/tenancy_dable/models/tenant_model.rb` | 04 |
| `TenancyDable::MembershipModel` | `lib/tenancy_dable/models/membership_model.rb` | 04 |
| `TenancyDable::UserModel` | `lib/tenancy_dable/models/user_model.rb` | 04 |
| `TenancyDable::Controller::Resolvable` | `lib/tenancy_dable/controller/resolvable.rb` | 05 |
| `TenancyDable::Policy::Context` | `lib/tenancy_dable/policy/context.rb` | 06 |
| `TenancyDable::Policy::Base` (+ `::Scope`) | `lib/tenancy_dable/policy/base.rb` | 06 |
| `TenancyDable::Generators::InstallGenerator` (`tenancy_dable:install`) | `lib/generators/tenancy_dable/install/install_generator.rb` (+ `templates/`) | 07 |
| `TenancyDable::Generators::ModelGenerator` (`tenancy_dable:model`) | `lib/generators/tenancy_dable/model/model_generator.rb` (+ `templates/`) | 07 |

Additive seams reserved by this design (beyond the frozen file list — see §10,
and the v0.3.0 additions in §14):

| Symbol | File | Implemented in |
|---|---|---|
| `TenancyDable::Job` (ActiveJob tenant propagation; also carries membership in v0.3.0 — §14.2) | `lib/tenancy_dable/job.rb` | 13 (membership: v0.3.0 phase 01) |
| `TenancyDable::Channel` (Action Cable tenant resolution, opt-in — §14.1) | `lib/tenancy_dable/channel.rb` | v0.3.0 phase 02 |
| `TenancyDable::Declarations` + `TenancyDable::Declaration` (`tenant_global`, declared tenancy — §16.3) | `lib/tenancy_dable/declarations.rb` | v0.5.0 W2 |
| `TenancyDable::Audit` + `Audit::Finding` (`TenancyDable.audit` — §16.3) | `lib/tenancy_dable/audit.rb` | v0.5.0 W2 |
| `rake tenancy_dable:audit` (§16.3) | `lib/tenancy_dable/tasks/audit.rake` | v0.5.0 W2 |
| `TenancyDable::Snapshot` (`TenancyDable.snapshot` / `carry` — §16.4) | `lib/tenancy_dable/snapshot.rb` | v0.5.0 W4 |
| Gem locales (validation messages — §16.6) | `lib/tenancy_dable/locale/{en,pt-BR}.yml` | v0.5.0 foundation |

---

## 2. Load / dependency graph

Require order at boot, and what depends on what. Arrows mean "loads / requires /
is wired by". Generators are **not** required at boot — Rails auto-discovers
them on the `lib/generators` path only when a generator command runs.

```
                       lib/tenancy_dable.rb  (ENTRY + facade)
                                  │
            ┌─────────────────────┼──────────────────────┐
            ▼                     ▼                      ▼
   version.rb            configuration.rb            errors.rb
   (VERSION)            (Configuration)        (Error + 8 subclasses)
                                  │
                                  ▼
                             current.rb
                  (Current < CurrentAttributes)
                                  │
                                  ▼
                             railtie.rb  ───────────────────────────────┐
                  (requires submodules; on_load wiring)                  │
                                  │                                      │
        ActiveSupport.on_load(:active_record)        ActiveSupport.on_load(:action_controller)
                                  │                                      │
            ┌─────────────────────┼───────────────┐                     │
            ▼                     ▼               ▼                      ▼
      scoped.rb        relation_extension.rb    models/*.rb       controller/resolvable.rb
   (Scoped concern,   (prepended to            (TenantModel,      (Resolvable concern,
    belongs_to_tenant) AR::Relation)            MembershipModel,   resolve_tenant!)
            │                                    UserModel)              │
            │                                        │                   │ uses membership_for
            └────────────────────────────────────────┴───────────────────┘
                                  │
                                  ▼
                             policy/*.rb
                 (Policy::Context, Policy::Base + Scope)
                                  │
                                  ▼
       lib/generators/tenancy_dable/{install,model}/*  (loaded on demand by Rails)
```

Key dependency facts downstream workers must honor:

- **`errors.rb` has no dependencies** — load it early; every other unit may raise
  its classes.
- **`current.rb` depends on nothing but ActiveSupport** — the `TenancyDable.*`
  facade in the entry file delegates to `Current` and reads `Configuration`.
- **`scoped.rb` / `relation_extension.rb` depend on `current` + `errors` +
  `configuration`** and are wired on `:active_record`.
- **`models/membership_model.rb` deliberately does NOT depend on `scoped.rb`** —
  it is queried before a tenant is active (see §5.3).
- **`controller/resolvable.rb` depends on `models` (`membership_for`) +
  `configuration` + the facade** and is wired on `:action_controller`.
- **`policy/*.rb` depends on `configuration` (roles/manager_roles/tenant_fk)**;
  `Policy::Context` is a pure `Data` type with no AR dependency.

---

## 3. `TenancyDable` facade — `lib/tenancy_dable.rb`

The module is the public entry point. The two config methods + `Error` base + a
`reset_configuration!` test hook already exist; Phase 02 adds the rest.

```ruby
module TenancyDable
  class Error < StandardError; end          # base for all gem errors (§7)

  class << self
    # --- configuration ---------------------------------------------------
    def configure                            # yields Configuration; returns it
    def configuration                        # memoized Configuration
    def reset_configuration!                 # test/boot reset hook (additive, §10-F)

    # --- current context (delegates to Current; §4) ----------------------
    def current_tenant                       #=> tenant instance | nil
    def current_tenant=(tenant)              # runs audit-override check (§4.2)
                                             #   + fires RLS hook when config.rls
    def current_membership                   #=> membership of the current tenant | nil
    def foreign_membership?                  #=> membership set, but not the current tenant's (v0.4.0, §15)
    def current_membership=(membership)
    def with_tenant(tenant) { ... }          # set tenant for block; ensure-restore
    def without_tenant { ... }               # set tenant_scope_disabled; ensure-restore

    # --- authorization builder (additive, introduced Phase 06; §6) -------
    def pundit_context(user:, tenant:, membership:)  #=> Policy::Context
  end
end
```

Return-shape contract:
- `current_tenant` returns the live AR instance stored in `Current`, or `nil`.
  `current_membership` returns the stored membership only while its `tenant_id`
  is the current tenant's id, else `nil` (v0.4.0, §15).
- `with_tenant` / `without_tenant` return the **block's** return value and
  **always** restore the prior `Current` state via an `ensure` block (nesting-safe).
- `current_tenant=` is the **only** place the audit-override policy and the RLS
  hook fire (§4.2). Assigning the *same* tenant is a no-op for audit purposes.

---

## 4. `TenancyDable::Configuration` & `TenancyDable::Current`

### 4.1 `Configuration` — `lib/tenancy_dable/configuration.rb`

Plain accessor object. **Every setting + default below is frozen** (verbatim from
the PLAN contract table). Phase 02 replaces today's empty stub.

| Setting (accessor) | Default | Type / meaning |
|---|---|---|
| `tenant_model` | `"Tenant"` | String — workspace model name |
| `user_model` | `"User"` | String — global identity model name |
| `membership_model` | `"Membership"` | String — join model name |
| `roles` | `%w[owner admin member]` | Array<String>, ordered highest-first; predicates derive from this |
| `manager_roles` | `%w[owner admin]` | Array<String> — the "can manage workspace" set |
| `tenant_fk` | `:tenant_id` | Symbol — FK on scoped models |
| `slug_param` | `:tenant_slug` | Symbol — URL param for resolution |
| `require_tenant` | `false` | Bool **or** callable — when truthy in ctx, unscoped query on a scoped model raises `NoTenantError` |
| `rls` | `false` | Bool — when true, fire `rls_statement` on tenant change |
| `rls_statement` | `->(t) { "SET app.tenant_id = #{quote(t&.id)}" }` | callable(tenant) → SQL String emitted on tenant change |
| `audit_overrides` | `:log` | `:log` / `:raise` / `:ignore` — behavior when `current_tenant` is reassigned to a **different** tenant |
| `on_tenant_not_found` | `:raise` | `:raise` (→ `ActiveRecord::RecordNotFound`) / `:null` (→ nil tenant) |
| `on_not_a_member` | `:not_a_member_error` | **(v0.2.0, additive)** host-selectable behavior when the acting user is not a member of the resolved tenant: `:not_a_member_error` (DEFAULT → raise `NotAMemberError`, today's behavior) / `:not_authorized` (→ raise `Pundit::NotAuthorizedError`; Pundit required lazily at the call site) / callable `->(tenant)` (run via `instance_exec` in the controller with the resolved tenant as the sole arg — redirect, custom error, `head :forbidden`, …) |
| `current_user_resolver` | `-> { defined?(Current) && Current.respond_to?(:user) ? Current.user : nil }` | callable → acting user (auth-agnostic) |

**Settings count: 14** — the 13 frozen at v0.1.0 plus `on_not_a_member` (added in
v0.2.0; additive, default `:not_a_member_error` preserves behavior — see §13). The
contract-lock spec (`spec/contract_spec.rb`) enumerates the frozen defaults; nits
phase 02 adds `on_not_a_member` to that list.

Validation (Phase 02): raise **`ConfigurationError`** on bad config — at minimum
`roles` empty, `manager_roles ⊄ roles`, a blank model name, or an `on_not_a_member`
symbol that is neither `:not_a_member_error` nor `:not_authorized` (a callable is
accepted as-is). Helpers the rest of the gem relies on (resolve constants from the
string names):

```ruby
def tenant_class      #=> tenant_model.constantize
def user_class        #=> user_model.constantize
def membership_class  #=> membership_model.constantize
def role?(name)       #=> roles.include?(name.to_s)
def manager_role?(name) #=> manager_roles.include?(name.to_s)
```
*(These resolver helpers are the conventional surface implied by "model names" +
"predicates generated from this"; they are internal conveniences, not new
public guarantees — see §10-E. Exact private/public split is Phase 02's call,
but the **settings and their defaults above are frozen.**)*

### 4.2 `Current` — `lib/tenancy_dable/current.rb`

```ruby
class TenancyDable::Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :membership, :tenant_scope_disabled
end
```

- Stores **only** these three attributes. The behavioral facade
  (`with_tenant`, `without_tenant`, audit/RLS hooks) lives on **`TenancyDable`**
  (§3), per PLAN ("Facade on `TenancyDable`"), not on `Current`.
- `tenant_scope_disabled` is the flag `without_tenant` toggles; the scoping
  engine (§5) and bulk-write guard read it.

**Audit-override policy** (fires inside `TenancyDable.current_tenant=`): when the
new tenant differs from the currently-set tenant, dispatch on `audit_overrides`:
`:log` → emit a log line **carrying tenant ids only** (invariant 6); `:raise` →
raise **`TenantOverrideError`**; `:ignore` → silent. Setting from `nil`, or to the
same tenant, is not an override.

**RLS hook**: when `config.rls` is truthy, after the tenant changes, execute
`config.rls_statement.call(tenant)` against the AR connection (the integration +
scoping specs assert via a connection spy).

---

## 5. Scoping engine (Phase 03)

### 5.1 `TenancyDable::Scoped` — `lib/tenancy_dable/scoped.rb`

`ActiveSupport::Concern`. A model `include`s it to gain the macro.

```ruby
module TenancyDable::Scoped
  extend ActiveSupport::Concern

  class_methods do
    # Declare this model tenant-scoped on `name` (the belongs_to association).
    def belongs_to_tenant(name = :tenant, **opts)
      # 1. belongs_to name, **opts
      # 2. define class predicate: tenant_scoped? -> true
      # 3. default_scope (decision tree below)
      # 4. before_validation(on: :create): auto-assign fk from current_tenant when blank
      # 5. tenant_fk immutability guard (persisted + fk change -> TenantImmutableError)
      # 6. cross-tenant belongs_to validation (message from CrossTenantError::MESSAGE)
    end

    # Scope uniqueness of `fields` by the tenant fk (merges opts[:scope]).
    def validates_uniqueness_to_tenant(*fields, **opts)

    # Present (=> true) only on classes that called belongs_to_tenant.
    def tenant_scoped?  #=> true
  end
end
```

**`default_scope` decision tree (FROZEN — fail-closed semantics, invariant 1):**

```
if    Current.tenant_scope_disabled        → all                       # without_tenant bypass
elsif TenancyDable.current_tenant present  → where(tenant_fk => current_tenant.id)
elsif require_tenant truthy-in-context     → raise NoTenantError        # FAIL-CLOSED
else                                       → all                        # fail-open (default)
```
`require_tenant` "truthy-in-context": if callable, `call` it and test the result;
if a plain bool, use it directly. The filter is applied via `where`, i.e.
**before any ordering** (invariant 2).

**Immutability (invariant 3):** once persisted, assigning a different value to the
tenant fk raises **`TenantImmutableError`**. Auto-assign on create (step 4) is
allowed because the record is not yet persisted.

**Cross-tenant `belongs_to` validation (invariant 2):** a `validate` callback that,
for any tenant-scoped association whose target carries a `tenant_id`, adds a
validation error sourced from **`CrossTenantError::MESSAGE`** (`"belongs to a
different tenant"` — the single source of truth for the string, additive in v0.2.0;
§7) when the target's tenant differs from the record's tenant. The validation
**adds an error, it does not raise** (the string is unchanged, so the existing
red-team/cross-tenant specs keep passing); the previously-dead class is now the
message's home. (The fixture's self-referential `widgets.parent_id` exercises this
— §8.)

### 5.2 `TenancyDable::RelationExtension` — `lib/tenancy_dable/relation_extension.rb`

Prepended to `ActiveRecord::Relation` by the railtie.

```ruby
module TenancyDable::RelationExtension
  def update_all(...)  ; guard! ; super ; end
  def delete_all(...)  ; guard! ; super ; end
  def destroy_all(...) ; guard! ; super ; end
end
```

**Bulk-write guard rule (FROZEN):**

```
return super UNLESS klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?   # non-scoped models untouched
return super IF    Current.tenant_scope_disabled                                # without_tenant bypass
raise BulkWriteError IF current_tenant.nil?                                      # no active tenant
raise BulkWriteError UNLESS relation is provably scoped to current_tenant.id     # mismatched / unscoped relation
super
```
So `Widget.update_all(...)` with no active tenant → `BulkWriteError`;
`Widget.where(tenant_id: other).delete_all` while tenant=A → `BulkWriteError`;
`TenancyDable.without_tenant { Widget.update_all(...) }` → allowed.

### 5.3 Why `MembershipModel` is *not* scoped

`Membership` is queried to *discover* a user's tenants **before** any tenant is
current (resolution, `membership_for`). Scoping it would create a chicken/egg
fail-closed deadlock. `MembershipModel` therefore **must not** include `Scoped`;
Phase 04 documents this inline, and Phase 09 asserts `Membership` is queryable
with no `current_tenant`.

---

## 6. Identity concerns (Phase 04)

All three are `ActiveSupport::Concern`s mixed into the host's AR models.

### 6.1 `TenancyDable::TenantModel` — `models/tenant_model.rb`
```ruby
# associations
has_many :memberships, dependent: :destroy
has_many :users, through: :memberships
# validations
validates :slug, presence: true, uniqueness: true, format: { ... }
before_validation :generate_slug   # slugify; append collision suffix on conflict
# instance
def owners   #=> the User records whose membership role is "owner"
```

### 6.2 `TenancyDable::MembershipModel` — `models/membership_model.rb`
```ruby
# associations
belongs_to :user
belongs_to :tenant
# validations
validates :role, inclusion: { in: TenancyDable.configuration.roles }
validates :user_id, uniqueness: { scope: :tenant_id }
# role predicates GENERATED from config.roles (not hard-coded): owner?, admin?, member?, ...
# scopes
scope :owners, -> { ... role == "owner" }
scope :admins, -> { ... role in manager_roles }
# guard
before_update :prevent_last_owner_demotion   # throw :abort when demoting the only owner
# instance
def manager?  #=> role ∈ config.manager_roles
# NOTE: deliberately does NOT include Scoped (see §5.3).
```
Role predicates derive from `config.roles` at include time — adding a role to the
config adds a predicate; nothing is hard-coded. Last-owner guard: demoting the
**only** owner is blocked (`throw :abort`, record stays invalid/unsaved);
demoting a non-last owner succeeds.

### 6.3 `TenancyDable::UserModel` — `models/user_model.rb`
```ruby
has_many :memberships, dependent: :destroy
has_many :tenants, through: :memberships
def membership_for(tenant)  #=> the Membership for tenant, or nil
def member_of?(tenant)      #=> boolean (membership_for(tenant).present?)
```
`membership_for(nil)` / a non-member tenant → `nil`; `member_of?` correspondingly
`false`.

---

## 7. Errors — `lib/tenancy_dable/errors.rb` (Phase 02)

All `< TenancyDable::Error` (which is `< StandardError`). Frozen set of 8, with
the trigger each one carries:

| Error | Raised when |
|---|---|
| `NoTenantError` | fail-closed: scoped query with `require_tenant` active and no current tenant (§5.1) |
| `TenantImmutableError` | reassigning a persisted record's tenant fk (§5.1, invariant 3) |
| `BulkWriteError` | guarded `update_all`/`delete_all`/`destroy_all` without a valid current-tenant scope (§5.2) |
| `CrossTenantError` | cross-tenant `belongs_to` reference — home of `MESSAGE = "belongs to a different tenant"` (constant additive in v0.2.0; the single source for the validation error string, §5.1). The validation *adds* this message, it does not raise. |
| `NotAMemberError` | resolved acting user is not a member of the resolved tenant (§9) |
| `TenantNotFoundError` | defined + reserved for host/`find_by` strategies (see §10-A) |
| `TenantOverrideError` | `current_tenant=` reassignment to a different tenant when `audit_overrides == :raise` (§4.2) |
| `ConfigurationError` | invalid configuration (empty roles, `manager_roles ⊄ roles`, blank model name) (§4.1) |

---

## 8. Combustion fixture schema (the harness Phase 01 must create)

Phase 01 builds `spec/internal/` with `db/schema.rb` containing **exactly** these
four tables. **Bold** columns are mandated by the PLAN contract; the rest are
the minimum test-support columns this design adds (rationale in §10-G/H).

```ruby
# spec/internal/db/schema.rb
ActiveRecord::Schema.define do
  create_table :tenants do |t|
    t.string :slug, null: false          # ← contract key (slug resolution)
    t.string :name                       # test-support label
    t.timestamps
  end
  add_index :tenants, :slug, unique: true

  create_table :users do |t|
    t.string :email                      # test-support identity attr
    t.timestamps
  end
  add_index :users, :email, unique: true

  create_table :memberships do |t|
    t.references :user,   null: false    # ← contract: user_id
    t.references :tenant, null: false    # ← contract: tenant_id
    t.string :role, null: false          # ← contract: role
    t.timestamps
  end
  add_index :memberships, [:user_id, :tenant_id], unique: true   # ← contract uniqueness

  create_table :widgets do |t|           # the scoped engine-test model
    t.references :tenant, null: false    # ← contract: tenant_id (the scope fk)
    t.string :name                       # ← contract: name
    t.references :parent                 # self-ref → exercises CrossTenantError (§10-G)
    t.timestamps
  end
  add_index :widgets, [:tenant_id, :name]   # non-unique: model-level
                                            # validates_uniqueness_to_tenant is the SUT
end
```

Models in `spec/internal/app/models` start **bare** (`Tenant`, `User`,
`Membership`, `Widget`); later phases mix the concerns in (`Widget` →
`include TenancyDable::Scoped` + `belongs_to_tenant` in Phase 03; identity
concerns in Phase 04). Factories (Phase 01): `tenant` (with slug), `user`,
`membership` (role), `widget`.

Why no DB-level unique constraint on `[tenant_id, name]`: Phase 08 tests
`validates_uniqueness_to_tenant` as the system-under-test; a DB unique index
would mask the model validation. The index stays **non-unique** for realism.

---

## 9. Slug resolution & authorization (Phases 05–06)

### 9.1 `TenancyDable::Controller::Resolvable` — `controller/resolvable.rb`
```ruby
module TenancyDable::Controller::Resolvable
  extend ActiveSupport::Concern
  class_methods do
    def resolve_tenant!(**before_action_opts)   # installs the before_action
  end
  # before_action body (private), in order:
  #   1. tenant = config.tenant_class.find_by!(slug: params[config.slug_param])
  #        honor on_tenant_not_found: :raise → ActiveRecord::RecordNotFound; :null → nil
  #   2. user   = instance_exec(&config.current_user_resolver)     # auth-agnostic
  #   3. membership = user&.membership_for(tenant); when absent, dispatch on
  #        config.on_not_a_member (v0.2.0): :not_a_member_error -> raise
  #        NotAMemberError (default, today's behavior); :not_authorized -> raise
  #        Pundit::NotAuthorizedError; callable -> instance_exec(tenant, &callable).
  #        resolve_tenant! signature unchanged.
  #   4. TenancyDable.current_tenant = tenant; .current_membership = membership
  def default_url_options  # merges { config.slug_param => TenancyDable.current_tenant&.slug }
end
```
**Slug only (invariant 5):** resolution reads `params[slug_param]` and calls
`find_by!(slug:)` — it never reads or trusts a tenant **id** from the URL.

### 9.2 `TenancyDable::Policy::Context` — `policy/context.rb`
```ruby
TenancyDable::Policy::Context = Data.define(:user, :tenant, :membership) do
  def role  #=> membership&.role   (nil membership → nil role)
end
```

### 9.3 `TenancyDable::Policy::Base` (+ `Scope`) — `policy/base.rb`
```ruby
class TenancyDable::Policy::Base
  def initialize(context, record)   # context is a Policy::Context
  # secure-by-default actions (all false unless a subclass overrides):
  def index?   = false
  def show?    = false
  def create?  = false
  def new?     = create?     # delegates
  def update?  = false
  def edit?    = update?     # delegates
  def destroy? = false

  private   # ← helpers private so pundit-matchers don't treat them as actions
  attr_reader :user, :tenant, :membership   # + role (from context)
  def role           #=> context.role
  def same_tenant?   #=> record.respond_to?(:tenant_id) && record.tenant_id == tenant&.id
  def owner?         #=> role == config.roles.first / "owner"
  def manager?       #=> role ∈ config.manager_roles
  def member?        #=> role present

  class Scope
    def initialize(context, scope)
    def resolve
      #   tenant nil → scope.none                         # FAIL CLOSED (invariant 4)
      #   else       → scope.where(config.tenant_fk => tenant.id)
    end
  end
end
```
Built via `TenancyDable.pundit_context(user:, tenant:, membership:)` (§3). The
`new?→create?` / `edit?→update?` delegation and the `respond_to?(:tenant_id)`
guard are refinements introduced in Phase 06 (§10-B/C); the secure-by-default
five (`index?/show?/create?/update?/destroy? → false`) are the frozen core.

---

## 10. Deviations & observations from `PLAN.md`

The **public surface stays frozen**. These are clarifications and additive seams
recorded here so downstream workers don't conflict.

- **A. `TenantNotFoundError` vs `ActiveRecord::RecordNotFound`.** The error
  hierarchy freezes `TenantNotFoundError`, but `on_tenant_not_found: :raise`
  resolves via `find_by!`, which raises `ActiveRecord::RecordNotFound` (Phases
  05 & 10 assert exactly that). **Resolution:** Phase 02 defines
  `TenantNotFoundError` as part of the frozen hierarchy (reserved for hosts and
  any non-bang `find_by` strategy), and the `Resolvable` `:raise` path raises
  `ActiveRecord::RecordNotFound` per the phase specs. No public symbol is
  dropped; the two coexist.
- **B. Policy `new?` / `edit?`.** PLAN lists the secure-by-default five
  (`index?/show?/create?/update?/destroy?`). Phase 06 additionally defines
  `new? → create?` and `edit? → update?`. Additive (Rails-conventional); the
  frozen five keep returning `false` by default.
- **C. `same_tenant?` nil-safety.** PLAN: `record.tenant_id == tenant&.id`.
  Phase 06 hardens to `record.respond_to?(:tenant_id) && record.tenant_id ==
  tenant&.id` so the helper is safe on non-scoped records. Behavior-preserving.
- **D. Policy helpers are `private`.** Phase 06 makes `same_tenant?/owner?/
  manager?/member?` private so `pundit-matchers` doesn't treat them as policy
  actions. Implementation detail; no surface change.
- **E. Config resolver helpers** (`tenant_class`, `role?`, …) in §4.1 are
  conventional internal conveniences implied by "model names" + "predicates
  generated from this". The **frozen guarantee is the settings + defaults
  table**, not these helper names.
- **F. `TenancyDable.reset_configuration!`** already exists in the entry file as
  a test/boot reset hook. Not in the PLAN facade list; additive and retained.
- **G. `widgets.parent_id` (self-reference).** PLAN mandates `widgets(tenant_id,
  name)`. To let Phase 08 prove the **cross-tenant `belongs_to` validation**
  (`CrossTenantError`) without introducing a fifth table, the fixture adds a
  nullable self-referential `parent_id` to `widgets`. Test-support only.
- **H. `tenants.name`, `users.email`.** Convenience/identity columns beyond the
  contract's minimal column list, added so factories produce realistic records.
  Neither concern requires them; purely test-support.
- **I. `TenancyDable::Job` (ActiveJob propagation).** The mission and gemspec
  advertise "ActiveJob tenant propagation," and Phase 13 tests it, but the
  frozen file layout lists no symbol for it. **Resolution:** reserve the name
  `TenancyDable::Job` (concern at `lib/tenancy_dable/job.rb`), introduced in
  Phase 13 — an `around_perform` that captures `current_tenant&.id` at enqueue
  and restores it via `TenancyDable.with_tenant` on perform (serialize/
  deserialize round-trip). Additive new symbol; does not alter the frozen
  surface. If Phase 13 finds the contract does not require it, it documents the
  deferral there.

---

## 11. Security invariants → proving phase + spec

The 6 invariants from `PLAN.md §Security invariants`, each mapped to the phase
that implements it and the spec that proves it (final adversarial gate: Phase 15,
`phases/15-critic-hardening.md`).

| # | Invariant | Implemented | Proven by |
|---|---|---|---|
| 1 | **Fail-closed when configured** — `require_tenant` active + no tenant ⇒ raise `NoTenantError`, never silent `all` | 03 (`scoped.rb` default-scope tree, §5.1) | 08 `spec/scoping` (fail-closed example) + 15 audit |
| 2 | **No cross-tenant read path** — filter-by-tenant before ordering; bulk-writes guarded; resolution enforces membership | 03 (default scope + `relation_extension.rb`), 05 (membership) | 08 `spec/scoping` (excludes other tenant, bulk guard, cross-tenant belongs_to) + 10 `spec/resolution` + 13 `spec/integration` (isolation) + 15 (3-way cross-tenant attack) |
| 3 | **`tenant_id` immutable after create** ⇒ `TenantImmutableError` | 03 (`scoped.rb`, §5.1) | 08 `spec/scoping` (reassign raises) + 15 |
| 4 | **Pundit scope fails closed** — `scope.none` with no active tenant | 06 (`policy/base.rb` `Scope#resolve`, §9.3) | 11 `spec/policy` (`resolve` nil-tenant ⇒ none) + 15 |
| 5 | **Slug-only resolution** — never trust a tenant id from the URL | 05 (`controller/resolvable.rb`, §9.1) | 10 `spec/resolution` (numeric id in slug slot does not resolve) + 15 |
| 6 | **No PII/secret leakage** — audit logs carry tenant ids only, never payloads | 02 (`current_tenant=` audit-override `:log` path, §4.2) | 15 (grep audit — only tenant ids in log lines); no dedicated unit spec |

---

## 12. Acceptance self-check (Phase 00)

- ✅ Every symbol in the `PLAN.md` contract appears in §1 with a matching name
  and its file + implementing phase.
- ✅ Full public signatures (args + return shape) given per class (§3–§9).
- ✅ Load/dependency graph drawn in the PLAN-specified order (§2).
- ✅ All 6 security invariants restated with proving phase + spec (§11).
- ✅ Combustion fixture schema specified — `tenants(slug)`, `users`,
  `memberships(user_id, tenant_id, role)`, scoped `widgets(tenant_id, name)`
  (§8).
- ✅ Deviations recorded with rationale; public surface unchanged (§10).
- ✅ No file under `lib/` modified by this phase.

---

## 13. v0.2.0 nits delta (additive — frozen for the nits run)

> Authoritative for this run: `.midgal/NITS_PLAN.md`. The v0.1.0 contract above
> stays frozen **except** as amended here. All three fixes are **additive**:
> default behavior is unchanged, no host breaks, the error hierarchy stays at
> **8 classes**, and every frozen signature (the `TenancyDable` facade, `Scoped`,
> `Resolvable`, the policy classes) is untouched. No default that affects tenant
> isolation changes — the §11 security invariants hold as-is. This phase (nits 00)
> writes no `lib/` code; it only records the contract delta the later phases
> implement against.

**Version bump:** `TenancyDable::VERSION` `0.1.0` → **`0.2.0`** (additive new config
setting = MINOR). Default behavior unchanged, so no host breaks; `~> 0.1.0` pins
simply won't pick it up (expected pre-1.0). Bumped in nits phase 04.

### Fix A — generated `ApplicationPolicy` ships the `Context` alias
The install generator's `application_policy.rb.tt` template adds, inside the
generated `ApplicationPolicy`, the one-line alias

```ruby
Context = TenancyDable::Policy::Context  # so ApplicationPolicy::Context resolves for policy specs
```

plus a commented `pundit_user` example pointing at `TenancyDable.pundit_context(...)`.
**Generator/template change only** — the gem ships no `ApplicationPolicy`, and no
runtime lib symbol changes. (Without it, a host's `ApplicationPolicy <
TenancyDable::Policy::Base` cannot resolve `ApplicationPolicy::Context`, because the
constant lives in the enclosing `TenancyDable::Policy` module, not in `Base`, so
existing host policy specs that say `ApplicationPolicy::Context.new(...)` break on
adoption.) Implemented in nits phase 01; proven by `rspec spec/generators`.

### Fix B — `on_not_a_member` config setting (§4.1, §9.1)
New setting `on_not_a_member`, default `:not_a_member_error` (preserves today's
behavior). Accepted values:
- `:not_a_member_error` (**DEFAULT**) → raise `TenancyDable::NotAMemberError`,
- `:not_authorized` → raise `Pundit::NotAuthorizedError` (Pundit required lazily at
  the call site — it is already a runtime dep),
- a **callable** `->(tenant)` → run via `instance_exec` in the controller with the
  resolved tenant as the sole arg, for full host control (redirect, custom error,
  `head :forbidden`).

`Configuration#validate!` raises `ConfigurationError` for a symbol that is neither
known value; a callable is accepted as-is. `Resolvable`'s membership-missing branch
(§9.1 step 3) dispatches on this setting instead of always raising — its
`resolve_tenant!` signature is unchanged. **Settings count → 14.** Implemented in
nits phase 02 (and `spec/contract_spec.rb`'s frozen-defaults list gains
`on_not_a_member: :not_a_member_error`); proven by `rspec spec/resolution
spec/contract_spec.rb`.

### Fix C — `CrossTenantError::MESSAGE` (§5.1, §7)
`CrossTenantError` gains a single source of truth for its string (the class was
defined in the frozen 8-error hierarchy but previously never referenced):

```ruby
class CrossTenantError < Error
  MESSAGE = "belongs to a different tenant"
end
```

The cross-tenant `belongs_to` validation in `Scoped` sources its message from it —
`errors.add(reflection.name, TenancyDable::CrossTenantError::MESSAGE)`. The
validation still **adds** an error (it does **not** raise), and the message string
is byte-for-byte unchanged, so the existing red-team/cross-tenant specs stay green;
the previously-dead class is now the message's home. The class is **not** new (error
count stays 8) — only the constant is additive. Implemented in nits phase 03; proven
by `rspec spec/scoping`.

### Contract impact summary
- New config setting `on_not_a_member` (default `:not_a_member_error`) → **14
  settings** (was 13).
- `CrossTenantError::MESSAGE` constant — **additive**; error count stays **8 classes**.
- Generated `ApplicationPolicy` defines `Context = TenancyDable::Policy::Context` —
  **template-only**, no runtime surface change.
- Frozen `TenancyDable` facade / `Scoped` / `Resolvable` / policy signatures:
  **unchanged**.
- No default that affects isolation changes; security invariants (§11) hold as-is.

---

## 14. v0.3.0 delta — Action Cable + Job membership (additive — frozen for this run)

> Authoritative for this run: [`.midgal/V03_PLAN.md`](.midgal/V03_PLAN.md). The
> v0.1.0 surface (§1–§12) and the v0.2.0 delta (§13) stay frozen **except** as
> amended here. Both additions are **additive**: no frozen signature, no default,
> the **8-error count**, and the **14-setting count** are unchanged; the §11
> security invariants hold as-is (and invariant 5 — slug-only resolution — now
> also governs the Cable layer). This phase (v0.3.0 phase 00) writes no `lib/`
> code; it records the contract delta the later phases implement against.

**Scope guardrails (from V03_PLAN).** This run changes ONLY the `tenancy_dable`
gem — no host/skeleton adaptation. The gem does **not** own Cable authentication:
connection-level user identification stays the host's job (`identified_by
:current_user`); the gem ships no `Connection` concern and no cookie/session
parsing. The inherent, documented Job seams (enqueue-time capture; deleted-tenant
fail-open/closed) are correct and stay — v0.3.0 only extends them to carry
membership symmetrically.

**Version target:** `TenancyDable::VERSION` `0.2.0` → **`0.3.0`** (two additive
features = MINOR; default behavior unchanged, so no host breaks). No gemspec
runtime change: Action Cable, like ActiveJob, is an **optional, opt-in**
dependency — `rails` (a dev dep) already provides `actioncable` for the harness,
and a host gets it via `rails`. The bump lands in v0.3.0 phase 04; this phase only
records the target.

### 14.1 `TenancyDable::Channel` — `lib/tenancy_dable/channel.rb` (opt-in, v0.3.0 phase 02)

The Action Cable parallel to `Controller::Resolvable` (§9.1): it resolves the
tenant **per subscription, by slug**, enforces membership, and runs channel
actions inside the tenant context — so a channel's reads scope and its writes pass
the bulk-write guard exactly like a controller action's.

**Opt-in, like `Job` (§10-I).** This file is deliberately **not** required by the
gem entry point — a host that runs channels does `require "tenancy_dable/channel"`
— so Action Cable stays an OPTIONAL dependency. The including class must be an
`ActionCable::Channel::Base` subclass (it provides `params`, `stream_from`,
`reject`, and `perform_action`).

**The gem does NOT own Cable auth (guardrail).** Connection-level user
identification is the host's job: its `ApplicationCable::Connection` declares
`identified_by :current_user` and establishes it however it authenticates
(cookie/session/token). Action Cable exposes each `identified_by` attribute as a
delegated reader on the channel, so the concern simply **reads** `current_user`
off the connection — it never establishes it. One host line (`identified_by
:current_user`) is the entire requirement; the gem ships no auth code.

```ruby
module TenancyDable::Channel
  extend ActiveSupport::Concern

  # Resolve the tenant for THIS subscription by SLUG from the subscription params
  # (invariant 5 — never an id). Memoized for the subscription's lifetime; nil
  # when the slug param is absent or matches no tenant.
  def current_tenant
    #=> @_tenancy_dable_tenant ||= TenancyDable.configuration.tenant_class
    #        .find_by(slug: params[TenancyDable.configuration.slug_param])
  end

  # The acting user's membership in current_tenant, or nil. `current_user` comes
  # from the connection's `identified_by :current_user` (host-owned auth).
  def current_membership   #=> current_user&.membership_for(current_tenant)

  def tenant_member?       #=> current_membership.present?

  # Cable parallel to Resolvable's membership enforcement — call in #subscribed:
  # rejects the subscription unless the acting user is a member of current_tenant.
  def reject_unless_member!   #=> reject unless tenant_member?

  # Tenant-namespaced stream name (no cross-tenant stream): "tenant:<id>"
  # (+ ":<suffix>" when given). Call AFTER membership is confirmed.
  def stream_for_tenant(suffix = nil)   #=> stream_from "tenant:#{current_tenant.id}[:suffix]"

  # Run a block inside the resolved tenant context (tenant + membership both set),
  # for DB reads in #subscribed where there is no auto-wrap. The tenant + the
  # prior membership are restored on exit by with_tenant's ensure (§3).
  def with_tenant_context(&blk)
    #=> TenancyDable.with_tenant(current_tenant) {
    #        TenancyDable.current_membership = current_membership; blk.call }
  end

  # AUTO CONTEXT: every incoming channel action runs inside the tenant context.
  # Action Cable routes each client-invoked action method through #perform_action;
  # wrapping it (super inside with_tenant_context) makes action handlers
  # tenant-scoped exactly like controller actions — without each action method
  # having to remember to wrap itself. MUST stay PUBLIC (Action Cable dispatches
  # actions via an EXPLICIT receiver — subscription.perform_action(data) — so a
  # private override raises NoMethodError and breaks dispatch); it is NOT part of
  # the frozen surface (the six helpers above are).
  def perform_action(data)
    with_tenant_context { super }
  end
end
```

**Public surface (FROZEN names):** `current_tenant`, `current_membership`,
`tenant_member?`, `reject_unless_member!`, `stream_for_tenant`,
`with_tenant_context`. `#perform_action` is necessarily **public** — Action Cable
dispatches actions via an explicit receiver (`subscription.perform_action(data)`),
so a private override would raise `NoMethodError` and break dispatch — but it is
**not** part of the frozen surface; the six helpers above are what
`spec/contract_spec.rb` locks (responds-to), mirroring the `Job` seam lock
(§ contract spec). The memo ivars (`@_tenancy_dable_tenant` /
`@_tenancy_dable_membership`) are private instance state.

**Slug-only (invariant 5):** resolution reads `params[config.slug_param]` from the
subscription and calls `find_by(slug:)` — it never reads or trusts a tenant **id**
from the params. Cable resolution uses the non-bang `find_by` (nil-on-miss),
because a channel `reject`s rather than raising `RecordNotFound`; the
controller-only `on_tenant_not_found` setting is **not** consulted here (so no new
setting — count stays 14).

**Safe when no tenant resolves (fail-safe by design):**
- nil tenant ⇒ `current_membership` is nil ⇒ `tenant_member?` is false ⇒
  `reject_unless_member!` rejects the subscription (the secure outcome).
- `with_tenant_context` / the `perform_action` wrap with a nil tenant delegate to
  `TenancyDable.with_tenant(nil)` — unscoped/fail-open by default, or fail-closed
  under `require_tenant`, identical to every other entry point. A correctly-written
  channel calls `reject_unless_member!` in `#subscribed`, so an unauthorized
  subscription never reaches an action.
- `stream_for_tenant` is meant to be called only after membership is confirmed, so
  `current_tenant` is present when it streams.

Typical host usage (documented in phase 04 README; **not** shipped by the gem):

```ruby
# app/channels/application_cable/connection.rb — host-owned auth (the one requirement)
identified_by :current_user

# a host channel
class TenantChannel < ApplicationCable::Channel
  include TenancyDable::Channel
  def subscribed
    reject_unless_member!   # enforce membership (rejects when nil/unknown tenant)
    stream_for_tenant       # "tenant:<id>"
  end
  # every client-invoked action method below auto-runs inside the tenant context
end
```

### 14.2 `TenancyDable::Job` carries membership — `lib/tenancy_dable/job.rb` (v0.3.0 phase 01)

v0.1.0's `Job` (§10-I) propagates only the **tenant** across the enqueue→perform
boundary, so `current_membership` is `nil` inside `perform`. v0.3.0 carries the
**membership** too, so a job's context matches that of the request which enqueued
it (a job can ask "what role is the acting member?" the same way a controller can).

- A second namespaced payload key, `SERIALIZED_MEMBERSHIP_KEY =
  "tenancy_dable_membership_id"`, travels alongside the existing
  `SERIALIZED_TENANT_KEY` (`"tenancy_dable_tenant_id"`). `serialize` snapshots
  `TenancyDable.current_membership&.id`; `deserialize` reads it back out.
- `around_perform` reloads it (`config.membership_class.find_by(id:)`) and sets
  `TenancyDable.current_membership` for the duration of `perform` — set **inside
  the existing `with_tenant` block**. Because `with_tenant` captures and restores
  `previous_membership` in its `ensure` (§3, `lib/tenancy_dable.rb`), the whole
  context (tenant **and** membership) is torn back down after `perform`, so a
  pooled worker thread never leaks one job's membership into the next.
- **Backward compatible:** a payload enqueued by an older build (no membership
  key) restores a `nil` membership; tenant propagation is byte-for-byte unchanged.

**Inherent Job seams stay as-is — NOT caveats to "fix" (guardrail):**
- **Enqueue-time capture:** the tenant (and now membership) id is snapshotted at
  *enqueue*; if it changes before the worker runs, the job uses the enqueue-time
  value. Correct, and unchanged.
- **Deleted tenant / membership:** a since-deleted record reloads to `nil`, so the
  job performs under `with_tenant(nil)` (fail-open by default, fail-closed under
  `require_tenant`). Membership now follows the same rule, symmetrically.

`SERIALIZED_MEMBERSHIP_KEY` and the `current_membership` restore are additive; the
`Job` concern's existing surface (`SERIALIZED_TENANT_KEY`,
`tenancy_dable_tenant_id`, `serialize` / `deserialize`, the `around_perform`) is
unchanged.

### 14.3 Contract impact summary
- New opt-in concern `TenancyDable::Channel` (the six frozen helpers in §14.1) at
  `lib/tenancy_dable/channel.rb` — additive; **not** auto-required; added to the §1
  additive-seams inventory and to `spec/contract_spec.rb`'s locked surface
  (responds-to the six helpers, like the `Job` seam).
- `TenancyDable::Job` gains `SERIALIZED_MEMBERSHIP_KEY` and restores
  `current_membership`; existing tenant propagation unchanged.
- **Error count stays 8; settings count stays 14** — no new error class, no new
  config setting (Channel reuses `slug_param`; its resolution behavior is fixed,
  not configurable). Frozen `TenancyDable` facade / `Current` / `Scoped` /
  `Resolvable` / policy signatures: **unchanged**.
- `TenancyDable::VERSION` → **`0.3.0`** (additive; bumped in phase 04).
- Action Cable is an OPTIONAL, opt-in dependency (like ActiveJob) — no gemspec
  runtime change; `rails` already provides `actioncable` for the harness.
- Security: invariant 5 (slug-only) now also governs Cable resolution; no default
  affecting tenant isolation changes; the §11 invariants hold as-is.

---

## 15. v0.4.0 delta - `current_membership` follows the tenant

- `current_membership` returns the stored membership only while its `tenant_id`
  is the current tenant's id, else `nil`. The stored value is not touched, so
  `with_tenant` still restores it on exit.
- `foreign_membership?` (new) is true when a membership is stored but is not the
  current tenant's, including when no tenant is current (a `Job` whose tenant
  was deleted runs under `with_tenant(nil)`). A host that treats a nil
  membership as a system context checks it.
- `Job#serialize` reads the stored membership (`Current.membership`) instead of
  `current_membership` (amends §14.2), so the payload is unchanged.
- Version `0.4.0`: a changed return value on a frozen reader plus one facade
  method. Errors stay 8, settings stay 14.

---

## 16. v0.5.0 delta - read guard, declared tenancy, fiber safety, audited bypass

> Frozen for the v0.5.0 run, which answers a production consumer's proposals. The
> v0.1.0 surface (§1-§12) and the deltas §13-§15 stay frozen **except** as amended
> here. This section amends §3 (facade), §4.1 (settings), §4.2 (isolation check),
> §5.1 (declaration step, create refusal), §5.2 (read guard), §7 (errors), §8
> (fixture schema) and §11 (invariants 2, 6, new 7). One release carries every
> item.
>
> Three changes are **on by default and can raise in a host that works today**:
> the read guard (`config.guard_reads = true`), the create refusal, and the
> isolation check (`config.isolation_check = :raise`). Each one refuses a
> cross-tenant leak that 0.4.0 lets through, and each has an explicit escape: a
> setting (`guard_reads = false`, `isolation_check = :warn`/`:off`), or a local
> `with_tenant(other) { ... }` / `without_tenant { ... }`. Everything else is
> additive. Pre-1.0, so this ships as a MINOR: `TenancyDable::VERSION` `0.4.0` →
> **`0.5.0`** (bumped at release, not by any workstream).
>
> Rails lines: the hook names, visibility and parameters below were read from the
> installed Active Record 7.1.6, 7.2.3 and 8.1.3 sources and measured by the P1
> probe on 7.1.6, 7.2.3.1, 8.1.3 and 8.1.4 (identical results on all four). 8.0 was
> not installed; it is taken as identical because 7.2 and 8.1 agree on every hooked
> method.

### 16.1 Read guard (§5.2, invariant 2)

**The leak (measured on 0.4.0, on every Rails line above).** While acting in tenant B,
every read through an association declared on the tenant model returns tenant
A's rows: `a.widgets.to_a`, `.first`, `.find`, `.find_by`, `.where(...)`,
`.count`, `.size`, `.pluck`, `.pick`, `.exists?`, `a.widget_ids`, `a.widgets.ids`,
`.find_each`, `.in_batches`, `.load_async`, the `async_*` calculations, and a
`has_one` (`a.first_widget`). So do `Widget.rewhere(tenant_id: a.id)`,
`Widget.all.merge(Widget.unscoped.where(tenant_id: a.id))`,
`Widget.unscope(where: :tenant_id)` (every tenant's rows), `Widget.unscope(:where)`,
and an `or` with another tenant's relation (`Widget.where(...).or(a.widgets)`).
Cause: an association's relation is `target_scope.merge!(association_scope)`, and
`WhereClause#merge` drops every predicate of the receiver on a column the other
side constrains, so the default scope's `tenant_id = <current>` is replaced by
the owner's `tenant_id = <owner>`. `where` appends instead (`tenant_id = B AND
tenant_id = A`, empty), which is why the existing red-team spec never saw it.

The same blind spot breaks a write: **`a.widgets.destroy_all` deletes tenant A's
rows while acting as B** (measured: A's rows 2 → 0). `CollectionProxy#destroy_all`
loads the target and destroys each record; it never calls
`Relation#destroy_all`, so the bulk-write guard does not run. The read guard
closes it: loading the target is refused, nothing is deleted.

**Hooks.** `RelationExtension` (prepended to `ActiveRecord::Relation`, §5.2) gains
six overrides, each `tenancy_guard_read!` then `super`, each with `(...)`
forwarding like the bulk-write overrides:

| Hook | Visibility (all lines) | Why it is needed |
|---|---|---|
| `exec_queries(...)` | private | every record load: `to_a`, `first`/`last`/`take`, `find`, `find_by`, `find_each`, `in_batches`, preloads, association readers, a scheduled `load_async` when read |
| `perform_calculation(...)` | private | `count`/`size`/`sum`/`average`/`minimum`/`maximum`, grouped calculations, `async_count` & co. |
| `pluck(...)` | public | `pluck`/`pick`/`async_pluck`, and `a.widget_ids` (`ids_reader` calls `scope.pluck`) |
| `exists?(...)` | public | `exists?`, `any?`/`empty?`/`none?` on an unloaded relation (calls `select_rows` directly) |
| `ids(...)` | public | `Relation#ids`/`async_ids`: builds its own select and calls `select_all`, skipping the three above |
| `load_async(...)` | public | with an async executor, schedules `exec_main_query` and skips `exec_queries`; hooking it refuses the query **before** it runs (without an executor it calls `load`, and the guard simply runs twice) |

The private hooks are defined under `private` in the module so the prepend keeps
them private. A scoped model's `find`/`find_by` never takes the statement-cache
path (its default scope makes `scope_attributes?` true), and an association reader
skips the association statement cache for the same reason, so both reach
`exec_queries` (measured).

**One shared classifier.** The read guard and the bulk-write guard both consume one
private method, so the pin they reason about cannot drift:

```ruby
# private, in RelationExtension. active_tenant is non-nil.
def tenancy_pin_state(active_tenant) #=> :current | :other | :removed | :unpinned
```

```
fk     = config.tenant_fk.to_s
pinned = where_values_hash[fk]   # top-level equality / IN predicates on klass.table_name;
                                 # when several constrain fk, the last one wins
:current   if !pinned.nil? && pinned.to_s == active_tenant.id.to_s
:other     if !pinned.nil?       # another id, or an Array (an IN list is a multi-tenant
                                 # read, even when it contains the current id)
:removed   if unscope_values contains :where, or a {where: cols} where any col names fk
           #   (a Symbol/String compares its last "."-separated segment, so
           #    "widgets.tenant_id" counts; an Arel attribute compares #name, which is
           #    how rewhere records its removals)
:removed   if a top-level Arel::Nodes::Grouping predicate references klass.table_name's fk
           #   (how `or` folds the tenant predicate into a disjunction). Top-level
           #    predicates are where_clause.ast.children when the ast is an
           #    Arel::Nodes::And, else [where_clause.ast]. The walk is duck-typed so it
           #    covers 7.1 (Or < Binary: left/right) and 7.2+ (Or < Nary: children):
           #    an Arel::Attributes::Attribute matches when name == fk and
           #    relation.name == klass.table_name; an Arel::Nodes::HomogeneousIn
           #    recurses into #attribute; an Array into its elements; any other node
           #    into #children, #left/#right and #expr where it responds to them.
:unpinned  otherwise
```

The order is deliberate: a pin to the current tenant wins over a recorded removal,
so `rewhere(tenant_id: current.id)` and `unscope(where: :tenant_id).where(tenant_id:
current.id)` read only the current tenant and pass (measured). A `nil` pin
(`where(tenant_id: nil)`, or an unsaved owner's association) is `:unpinned`: the
default scope's predicate is still ANDed in, so it returns nothing (measured).

**Read-guard decision tree (FROZEN):**

```
return               UNLESS config.guard_reads                                # escape hatch (default true)
return               UNLESS klass.respond_to?(:tenant_scoped?) && klass.tenant_scoped?
return               IF     Current.tenant_scope_disabled                      # without_tenant
return               IF     TenancyDable.current_tenant.nil?                   # the default scope decides:
                                                                               #   NoTenantError or unscoped
raise CrossTenantReadError IF tenancy_pin_state(current) is :other or :removed
return                                                                         # :current, :unpinned
```

**Bulk-write guard (§5.2) - behaviour unchanged, rewritten on the classifier:**
raise `BulkWriteError` when there is no current tenant (as today), else raise
`BulkWriteError` unless `tenancy_pin_state(current) == :current`. That is exactly
the 0.4.0 rule ("not equality-pinned to the current tenant's id"), with today's two
messages. `config.guard_reads` does not affect it.

**What passes, on purpose (measured):** `b.widgets` and its `ids`, a preload of the
current tenant's owners (`Tenant.where(id: b.id).includes(:widgets)`: a one-element
key list becomes an equality), `Widget.count`, `widget.reload`, `unscope(where:
:name)` (only the tenant FK counts: hosts unscope other columns legitimately),
`eager_load` from the tenant side (the join keeps the default scope: `[]`), an
association pinned on another column (`widget.children`: the default scope stays),
everything inside `without_tenant`, and `Model.unscoped` with no tenant pin. The
last one is the explicit Active Record bypass and must keep passing: Rails' own
`UniquenessValidator` builds on `klass.unscoped` (so a plain global
`validates :x, uniqueness: true` on a scoped model works), `reload` runs inside
`unscoped { }`, and the gem's cross-tenant `belongs_to` check uses
`unscoped.where(id:).pick(fk)`.

**Newly refused (contract change, measured):** `Widget.where(tenant_id: other)` and
`Widget.where(tenant_id: [a, b])` (0.4.0: empty / the current tenant's rows only),
a preload of another or of several tenants' owners (`Tenant.where(id: [a, b])
.includes(:widgets)`), `Widget.unscoped.where(tenant_id: other)`, destroying
another tenant whose `dependent:` associations must be loaded, and an `or` that
mixes the tenant predicate into a disjunction. Code that pins another tenant is a
bug whether it gets nothing or something back; the fix is
`with_tenant(other) { ... }`, or a deliberate `without_tenant { ... }`.

**Residuals (documented limits, like the bulk-write guard's).** A relation whose
where clause no longer mentions the tenant FK and that recorded no removal is
indistinguishable from `Model.unscoped`, and passes: `Model.unscoped` itself (and
`unscoped.where.not(tenant_id: x)`), `Model.unscoped { }`, `except(:where)`,
`only(...)` without `:where`, and an `or` with such a relation
(`Widget.all.or(Widget.unscope(where: :tenant_id))`, whose disjunction Active
Record collapses to "no predicate"). So do SQL-string predicates
(`where("tenant_id = ?", x)`) and raw SQL (`find_by_sql`, `connection.select_all`).
All of these are explicit relation surgery; the guard targets the shapes Active
Record produces on its own (association merge, `rewhere`, `merge`, `unscope`,
`or`).

**Error.** `TenancyDable::CrossTenantReadError < TenancyDable::Error`, sibling of
`BulkWriteError`. Message: `"refusing to read #{klass.name} "` followed by
`"pinned to tenant #{pinned.inspect}"` (`:other`) or `"with the tenant filter
removed"` (`:removed`), then `" while acting in tenant ##{current.id}; enter the
tenant with TenancyDable.with_tenant, or wrap a deliberate cross-tenant read in
TenancyDable.without_tenant"`. Model name and tenant ids only (invariant 6).

**Setting.** `config.guard_reads`, default `true`. `false` restores the 0.4.0 read
behaviour (the create refusal in §16.2 is separate and stays on).

**Deviations from the proposal, decided here.** (1) The proposal shares a boolean
`pinned_to_another_tenant?`; "pinned to another tenant" cannot serve the
bulk-write guard, which also refuses an unpinned relation, so the shared unit is
the four-state classifier above. (2) The proposal's unscope check compared
`u[:where]` with `to_s`; that misses `unscope(where: "widgets.tenant_id")` (measured
leak), so a qualified name compares its last segment. (3) The proposal's rule lets
`Widget.where(...).or(a.widgets)` through (no top-level pin, no unscope; measured
leak); the disjunction rule closes it. (4) The `destroy_all` write leak above was
not in the proposal.

### 16.2 Creating into another tenant is refused (§5.1, invariant 2)

On 0.4.0, inside `with_tenant(b)`, `a.widgets.create!(...)`,
`Widget.create!(tenant: a)`, `Widget.create!(tenant_id: a.id)` and
`Widget.new(tenant_id: a.id).save(validate: false)` all persist a row in tenant A
(measured, with and without a uniqueness validation). The auto-assign fills only a
blank FK, the cross-tenant `belongs_to` check skips the tenant association, and
immutability applies only after persist. With the read guard on, the same create
would raise `CrossTenantReadError` for a model that calls
`validates_uniqueness_to_tenant` (its `exists?` is a read pinned to A) and succeed
for one that does not. The maintainer chose to **refuse** it.

**Rule (FROZEN).** On create of a tenant-scoped record:

```
return IF record[fk].blank?                      # blank: auto-assign (§5.1 step 4) decides, unchanged
return IF Current.tenant_scope_disabled          # without_tenant: unchanged
return IF TenancyDable.current_tenant.nil?       # no current tenant: unchanged (0.4.0)
return IF record[fk].to_s == current_tenant.id.to_s
raise CrossTenantWriteError
```

**Mechanism.** `belongs_to_tenant` installs the rule twice, as two prepended
callbacks that share one private instance method defined in `Scoped`,
`tenancy_refuse_foreign_tenant!(fk)`, each called with the FK bound at declaration
(like every other step of §5.1):

- `before_validation(on: :create, prepend: true)`: runs before every validator,
  whatever validators the model has, so `validates_uniqueness_to_tenant` (or any
  validator that reads) never runs first and the error is always
  `CrossTenantWriteError`, never `CrossTenantReadError` (measured with the
  prototype: both `Widget`, which has the uniqueness validation, and a model
  without one raise the write error);
- `before_create(prepend: true)`: covers `save(validate: false)`, which skips the
  validation callbacks, and checks the FK as it is finally written (after
  `before_save` callbacks such as a `belongs_to` autosave have run).

Both run in the validated path; the check is one comparison. `config.guard_reads`
does not affect it. There is no setting for it: like immutability (invariant 3) it
is a rule, and the local escape is explicit (`with_tenant(target) { create }`, or
`without_tenant { create }`).

**Raise, not a validation error (decided).** The tenant FK of a new record is not
user input in a correctly built host (it comes from the current tenant or from
code), so a mismatch is a programming error, and a form message ("Tenant belongs
to a different tenant") would be meaningless to an end user. A raise also behaves
the same under `save(validate: false)`, where a validation error would be skipped,
and matches the other write refusals (`BulkWriteError`, `TenantImmutableError`).
The cross-tenant `belongs_to` check keeps adding a validation error (§5.1): its
input (a parent id) plausibly does come from a form. `valid?` on such a new record
raises too, which is intended (fail fast).

**Error.** `TenancyDable::CrossTenantWriteError < TenancyDable::Error`. Message:
`"refusing to create #{self.class.name} in tenant ##{record[fk]} while acting in
tenant ##{current.id}; enter the tenant with TenancyDable.with_tenant"`. Ids only.
English, like every exception message; it adds nothing to `errors`, so it has no
I18n key.

**Unchanged and out of scope.** `save(validate: false)` with a blank FK still
skips the auto-assign (0.4.0). `insert_all` skips callbacks, but called on a scoped
model inside a tenant it applies the default scope's attributes, so a row given
another tenant's FK lands in the CURRENT tenant (measured on 7.1, 7.2 and 8.1): it
cannot create into another tenant. `upsert_all` was not measured and is not
guarded; with a unique index that spans tenants, its conflict update could touch
another tenant's row (a residual, like raw SQL).

**Spec flip.** `spec/scoping/tenant_assignment_spec.rb:19` ("does not override an
explicitly provided tenant_id") becomes "refuses an explicitly provided tenant_id
of another tenant" and expects `CrossTenantWriteError`; a sibling example keeps
the explicit FK accepted when it IS the current tenant, and when there is no
current tenant.

### 16.3 Every model declares its tenancy, and an audit proves it (§5.1)

A model that includes `Scoped` and calls `belongs_to_tenant` is protected; any
other model is global, and nothing tells "global by decision" from "global by
forgetting". v0.5.0 makes the decision explicit and auditable.

**Installation.** The railtie's `install_active_record!` requires
`tenancy_dable/declarations` and runs `ActiveRecord::Base.extend(TenancyDable::Declarations)`,
so every Active Record class (a host's, and a library's that inherits
`ActiveRecord::Base` directly) has the macro and the readers. `Scoped` stays a
separate, explicit `include`.

```ruby
module TenancyDable
  # One model's tenancy decision (frozen value object).
  #   kind            :scoped | :global
  #   reason          String for :global, nil for :scoped
  #   tag             Symbol | String | nil  (free-form; a host builds its own grouping on it)
  #   allow_tenant_fk true | false           (always false for :scoped)
  Declaration = Data.define(:kind, :reason, :tag, :allow_tenant_fk)

  module Declarations                      # extended onto ActiveRecord::Base
    def tenant_global(because:, tag: nil, allow_tenant_fk: false)  #=> Declaration
    def tenancy_declaration                #=> Declaration | nil (own, else inherited)
    def tenancy_global_reason              #=> tenancy_declaration&.reason
    def tenancy_tag                        #=> tenancy_declaration&.tag

    private

    # The single writer; tenant_global and belongs_to_tenant both call it.
    def tenancy_declare!(kind, reason: nil, tag: nil, allow_tenant_fk: false)  #=> Declaration
  end
end
```

**`tenancy_declare!` rule (FROZEN),** checked in this order, each failure raising
`ConfigurationError` before anything is stored:

1. `kind == :global` and `reason` is not a String with non-whitespace content →
   `"#{name}: tenant_global requires a non-blank because: reason"`;
2. `tag` is not `nil`, a Symbol or a String → `"#{name}: tag must be a Symbol or String"`;
3. `allow_tenant_fk` is not `true`/`false` → `"#{name}: allow_tenant_fk must be true or false"`;
4. `tenancy_declaration` is already present, declared on this class OR inherited →
   `"#{name} already declared its tenancy (#{existing.kind}); a declaration cannot be changed"`.

Then it stores `Declaration.new(kind:, reason: reason&.dup&.freeze, tag:,
allow_tenant_fk:)` in the class's own `@tenancy_declaration` and returns it
(`name` above reads `name || "an anonymous model"`). `ConfigurationError` is reused
on purpose: a bad declaration is a misconfiguration found at class load, and the
error count stays lean.

**Readers and inheritance.** `tenancy_declaration` returns the class's own
declaration, else its superclass's (`ActiveRecord::Base` has none). So an STI
subclass, or a subclass of a declared abstract class, is declared by inheritance,
and any second declaration anywhere on a lineage raises: a scoped table cannot be
re-declared weaker in a subclass, and `tenant_global` on `ApplicationRecord` is
refused below it (a blanket global base is "global by forgetting" in disguise).
`tenant_scoped?` is unchanged: still defined ONLY on scoped classes, because the
guards discriminate on `respond_to?(:tenant_scoped?)`.

**`belongs_to_tenant(name = :tenant, tag: nil, **opts)`.** Its first statement is
`tenancy_declare!(:scoped, tag: tag)`, so a re-declaration raises before the
`belongs_to` or any callback is installed. `tag:` is consumed by the macro and is
never forwarded to `belongs_to` (which would reject it). Every other step of §5.1
is unchanged; §16.2 adds the create refusal.

**The gem's identity concerns declare themselves**, as the first statement of
their `included do` blocks, so a host's audit is clean without host code:

| Concern | Declaration |
|---|---|
| `TenantModel` | `tenant_global because: "the tenant model is the tenancy boundary itself"` |
| `UserModel` | `tenant_global because: "a user spans tenants through memberships"` |
| `MembershipModel` | `tenant_global because: "memberships are read before any tenant is current (DESIGN.md §5.3)", allow_tenant_fk: true` |

`allow_tenant_fk: true` is how a deliberately unscoped table that carries the
tenant FK (memberships, and in a host e.g. invitations looked up by token before
resolution) says so, in its own declaration, so the audit's
`:global_with_tenant_fk` finding stays meaningful for everything else. A host model
that includes one of these concerns must not declare again (it raises).

**Audit API.**

```ruby
module TenancyDable
  module Audit
    KINDS = %i[undeclared global_with_tenant_fk scoped_without_index].freeze

    Finding = Data.define(:model, :kind, :message) do  # model: the class; kind: one of KINDS
      def to_s = "#{model.name}: #{message}"
    end

    def self.run(models = nil)  #=> frozen Array<Finding>
  end

  def self.audit(models = nil) = Audit.run(models)   # facade (§3)
end
```

**`Audit.run` rule (FROZEN).**

```
candidates =
  if models.nil?
    ::Rails.application.eager_load! if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
    ActiveRecord::Base.descendants.select { |m| m.name.present? && m.name.safe_constantize.equal?(m) }
                                     # drops anonymous classes and classes whose constant was
                                     # removed or reloaded (stale descendants)
  else
    Array(models)                    # as given: no eager load, no name filter
  end

skip a model when (name = m.name.to_s):
  m.abstract_class?
  m.base_class != m                                   # STI subclass: its base class answers for the table
  name == ns.to_s || name.start_with?("#{ns}::") for any ns in config.audit_ignored_namespaces
  config.audit_allowed.key?(name)

findings per remaining model (fk = config.tenant_fk.to_s, d = m.tenancy_declaration):
  :undeclared             d.nil?
  :global_with_tenant_fk  d&.kind == :global && !d.allow_tenant_fk &&
                          m.table_exists? && m.column_names.include?(fk)
  :scoped_without_index   d&.kind == :scoped && m.table_exists? &&
                          Array(m.primary_key).first.to_s != fk &&
                          m.connection_pool.with_connection { |c| c.indexes(m.table_name) }
                            .none? { |index| Array(index.columns).first.to_s == fk }

sorted by [name, KINDS.index(kind)], frozen
```

Messages: `:undeclared` → `"declares no tenancy; add belongs_to_tenant, or
tenant_global because: \"...\""`; `:global_with_tenant_fk` → `"is declared
tenant_global but has a #{fk} column; scope it with belongs_to_tenant, or pass
allow_tenant_fk: true if it is deliberately unscoped"`; `:scoped_without_index` →
`"is tenant-scoped but no index leads with #{fk}"`. A composite index whose first
column is the FK counts (the harness's `widgets[tenant_id, name]`), and so does a
composite primary key that leads with it. A model whose table does not exist yet
is still checked for `:undeclared` and skips the two schema checks. The audit
reads only class metadata and the schema: no rows, nothing raised for a finding.
`connection_pool.with_connection` is used because it exists on every supported
line (`ActiveRecord::Base.with_connection` is 7.2+).

**Settings.**

| Setting | Default | `validate!` raises `ConfigurationError` unless |
|---|---|---|
| `audit_ignored_namespaces` | `%w[ActiveStorage ActionText ActionMailbox SolidQueue SolidCache SolidCable]` (a new Array per `Configuration`, not frozen, so a host can `+=`) | it is an Array of non-blank Strings or Symbols |
| `audit_allowed` | `{}` | it is a Hash whose keys are non-blank Strings (model names) and whose values are non-blank Strings (the reason) |

`audit_allowed` is for records the host does not own and has reviewed (a library
model that inherits `ActiveRecord::Base`); the reason lives in one place. A host's
own model declares itself instead.

**Rake task.** `lib/tenancy_dable/tasks/audit.rake`, loaded by the railtie's
`rake_tasks do load File.expand_path("tasks/audit.rake", __dir__) end`:

```ruby
namespace :tenancy_dable do
  desc "Report models whose tenancy is undeclared or suspicious (exits 1 on findings)"
  task audit: :environment do
    findings = TenancyDable.audit
    abort(findings.join("\n")) if findings.any?
    puts "tenancy_dable:audit: every model declares its tenancy"
  end
end
```

Exit status `0` and one line on stdout when clean; status `1` with one finding per
line on stderr otherwise. It audits after eager loading (`TenancyDable.audit` with
no argument eager-loads), so a development `rake` run sees every model. A host's
spec can call `expect(TenancyDable.audit).to be_empty`.

**Compatibility.** Additive: nothing raises at boot unless a model calls
`tenant_global` incorrectly or declares twice, and the audit runs only when called.

### 16.4 Fiber safety: the isolation check and the context carrier (§3, §4.2)

**Problem.** `Current` is a `CurrentAttributes`, isolated per thread under Rails'
default `isolation_level = :thread`. Under a fiber scheduler (a fiber-per-request
server, or anything on `async`), every fiber on a reactor thread shares it.
Measured on 8.1.4 inside `Async`: with thread isolation, one fiber reads the tenant
another fiber wrote (`["fb", "fb"]`); with `:fiber` isolation each keeps its own
(`["fa", "fb"]`). Separately, work handed to another thread starts with no tenant
(measured: `Thread.new { TenancyDable.current_tenant }.value` is `nil`), which is
safe (fail-closed) but makes concurrency impossible without hand-made plumbing.

**Isolation check (FROZEN).** A private facade method, `TenancyDable.check_isolation!`,
runs FIRST in every gem write to `Current`, before anything is written:

- `current_tenant=` (so `with_tenant` on entry AND on its ensure-restore, the
  controller, the Job and the Channel, which all write through the facade);
- `current_membership=`;
- the private writer of `tenant_scope_disabled` that `without_tenant` (§16.5) and
  `Snapshot#restore` use.

```
return IF config.isolation_check == :off                   # nothing is evaluated
return UNLESS Fiber.scheduler                              # no scheduler on this thread (Puma, Sidekiq, rake: no-op)
return UNLESS ActiveSupport::IsolatedExecutionState.isolation_level == :thread
:raise → raise UnsafeIsolationError, message                # default
:warn  → logger&.warn("[TenancyDable] #{message}") on every detected write, then write
```

`message` (for both): `"tenant state written under a fiber scheduler with thread
isolation; set config.active_support.isolation_level = :fiber"`. No ids. `logger`
is the facade's existing private logger (the one the audit-override `:log` path
uses). `Fiber.scheduler` (not `Fiber.current_scheduler`) on purpose: a
non-nil scheduler means fibers on this thread can interleave, even if the writing
fiber is blocking. `:warn` logs on every detected write (like `audit_overrides:
:log`), because the condition is a live cross-request leak, not a one-off.

**Setting.** `config.isolation_check`, default `:raise`; `validate!` raises
`ConfigurationError` unless it is `:raise`, `:warn` or `:off`. A host that already
runs fibers with thread isolation starts raising on the first tenant write, which
is the bug the check reports; `:warn`/`:off` are the documented escape.

**Context carrier (additive).**

```ruby
module TenancyDable
  # RAW stored state (§4.2), not the readers: `membership` is Current.membership,
  # so the §15 rule still holds on the other side.
  Snapshot = Data.define(:tenant, :membership, :tenant_scope_disabled) do
    def restore(&block)   #=> the block's value
  end

  def self.snapshot       #=> Snapshot.new(tenant: Current.tenant, membership: Current.membership,
                          #                tenant_scope_disabled: Current.tenant_scope_disabled)
  def self.carry(&block)  #=> a lambda (*args, **kwargs) running block inside the snapshot taken NOW
end
```

`Snapshot#restore` rule (FROZEN):

```
TenancyDable.with_tenant(tenant) do                 # current_tenant=: isolation check, audit override, RLS
  TenancyDable.current_membership = membership      # with_tenant's ensure restores the prior membership
  <private tenant_scope_disabled writer>(tenant_scope_disabled) { yield }   # restores the prior flag in ensure
end
```

- On normal exit and on raise, the tenant, membership and flag of the restoring
  thread or fiber go back to what they were before `restore`: `nil`/`nil`/`nil` on a
  fresh or pooled thread, so a pooled thread never keeps another request's tenant.
- The tenant goes through `current_tenant=` like `with_tenant`, so the RLS
  statement fires on entry and on restore. Restoring into a thread that is already
  in a DIFFERENT tenant is a tenant switch, exactly like a nested `with_tenant`: the
  audit-override policy (§4.2) applies.
- Restoring a snapshot taken inside `without_tenant` sets the flag without the
  reason check and without the §16.5 event: it is the same bypass, already reported
  where it began.
- Inside, `current_membership` follows §15: nil when the carried membership is not
  the carried tenant's.
- Without a block, `restore` and `carry` raise `LocalJumpError`, as `with_tenant`
  does.

`carry` is `snapshot = self.snapshot; ->(*args, **kwargs) { snapshot.restore {
block.call(*args, **kwargs) } }`: `Thread.new(&TenancyDable.carry { work })`,
`executor.post(&TenancyDable.carry { work })`.

**Specs and test dependency.** `async` becomes a development dependency
(`spec.add_development_dependency "async", "~> 2.0"`; releases from 2.44 need Ruby
3.3, and Bundler resolves an older 2.x on the Ruby 3.2 CI cells, since the lockfile
is not committed). Unit examples stub `Fiber.scheduler` and
`ActiveSupport::IsolatedExecutionState.isolation_level` to cover the three modes on
each writer; one integration example runs a real `Async { }` reactor with thread
isolation (raises) and with `:fiber` isolation (passes), restoring the level in
`ensure`. Snapshot examples cross `Thread.new` and an `Async` task. **Assert
`Current` state, never query, inside a spawned thread or fiber or while the
isolation level is toggled:** each of those checks out its own connection, outside
the example's transaction. Build records first.

### 16.5 An audited `without_tenant` (§3, invariant 6)

```ruby
TenancyDable::WITHOUT_TENANT_EVENT = "without_tenant.tenancy_dable"

def self.without_tenant(reason: nil)   #=> the block's value (signature change is additive)
```

**Order (FROZEN):**

1. `config.require_bypass_reason` is true and the reason is blank
   (`reason.nil? || reason.to_s.strip.empty?`) → raise `BypassReasonError`: no
   event, no state change;
2. the isolation check (§16.4);
3. when `ActiveSupport::Notifications.notifier.listening?(WITHOUT_TENANT_EVENT)`:
   `ActiveSupport::Notifications.instrument(WITHOUT_TENANT_EVENT, reason:,
   tenant_id: Current.tenant&.id, call_site:)`, **with no block**; with no
   subscriber, neither the event nor `call_site` is computed;
4. set `tenant_scope_disabled = true`, yield, restore the prior flag in `ensure`
   (the §3 guarantee, unchanged).

**Payload.** Exactly three keys. `reason`: the value passed, unchanged (`nil` when
omitted). `tenant_id`: the raw tenant active when the bypass starts (the bypass
does not change it), or `nil`. `call_site`: `"#{path}:#{lineno}"` of the first
`caller_locations` entry whose `absolute_path || path` does not start with the
gem's `lib/` directory (`"#{File.expand_path(__dir__)}/"` as seen from
`lib/tenancy_dable.rb`), or `nil` when there is none.

**Why no block.** Given a block, `ActiveSupport::Notifications` adds `:exception`
and `:exception_object` to the payload when the block raises, and an exception can
carry a record (`ActiveRecord::RecordInvalid#record`) that a subscriber logging the
payload would leak (invariant 6). Without a block the payload stays the three keys.
The event marks where a bypass begins; it has no meaningful duration. If a
subscriber raises, the bypass never starts (fail closed).

**Nesting.** Every call reports itself: a nested bypass emits a second event with
its own call site (and the same `tenant_id`). Each level restores the prior flag on
normal exit and on raise.

**Error and setting.** `TenancyDable::BypassReasonError < TenancyDable::Error`,
message `"without_tenant requires a non-blank reason: (config.require_bypass_reason
is on)"`. `config.require_bypass_reason`, default `false`; `validate!` raises
`ConfigurationError` unless it is `true` or `false`.

**Invariant 6.** The payload carries the host's reason, a tenant id and a
`file:line`, never a record; hosts should not put record data in a reason. The gem
persists nothing. No gem-internal code calls `without_tenant` today; any future
internal bypass passes a reason.

### 16.6 Localizable validation messages (§5.1, §6)

Every literal English string the gem adds to a record's `errors` becomes an error
key with an English default:

| Call site | 0.4.0 | 0.5.0 |
|---|---|---|
| `scoped.rb`, cross-tenant `belongs_to` check | `errors.add(reflection.name, CrossTenantError::MESSAGE)` | `errors.add(reflection.name, :cross_tenant)` |
| `models/membership_model.rb`, last-owner guard | `errors.add(:role, "cannot be changed: ...")` | `errors.add(:role, :last_owner)` |
| `models/tenant_model.rb:37`, slug format | `message: "must be lowercase ..."` | `message: :slug_format` (the error type stays `:invalid`) |

The create refusal (§16.2) raises, so it adds no message.

**Locale files** `lib/tenancy_dable/locale/en.yml` and
`lib/tenancy_dable/locale/pt-BR.yml` (inside `spec.files`, which ships `lib/**/*`).
The gem ships `pt-BR` beside `en` because the edidable family serves Brazilian
Portuguese hosts; any other locale is the host's to add:

```yaml
en:
  errors:
    messages:
      cross_tenant: "belongs to a different tenant"
      last_owner: "cannot be changed: a tenant must keep at least one owner"
      slug_format: "must be lowercase letters, numbers, and single hyphens"
```

```yaml
pt-BR:
  errors:
    messages:
      cross_tenant: "pertence a outro tenant"
      last_owner: "não pode ser alterado: um tenant precisa manter ao menos um proprietário"
      slug_format: "deve ter apenas letras minúsculas, números e hífens simples"
```

**Namespace (decided).** `errors.messages.<key>` is the LAST entry of Active
Model's lookup chain, so every host override wins, from the most specific
(`activerecord.errors.models.<model>.attributes.<attribute>.<key>`, then
`activerecord.errors.models.<model>.<key>`, `activerecord.errors.messages.<key>`,
`errors.attributes.<attribute>.<key>`). Defining the defaults under
`activerecord.errors.messages` would shadow a host's `errors.messages` override.

**Wiring.** The railtie adds

```ruby
initializer "tenancy_dable.i18n" do |app|
  app.config.i18n.load_path.unshift(*Dir[File.expand_path("locale/*.yml", __dir__)])
end
```

Unshifting into the application's list puts the gem's file before the host's own
locale files, so a host file loaded later overrides it; Rails copies the list into
`I18n.load_path` when I18n initializes, after all initializers.

**Compatibility.** `CrossTenantError::MESSAGE` stays, as a compatibility constant
equal to the `:en` default (contract-locked). In `:en`, `errors[:attribute]` and
`errors.added?(:parent, CrossTenantError::MESSAGE)` are unchanged; `errors.details`
now carries `error: :cross_tenant` / `error: :last_owner` instead of the English
String (the slug format error keeps `error: :invalid`). A host whose locale is
neither `:en` nor `:"pt-BR"` must translate the three keys, or enable
`config.i18n.fallbacks`; otherwise Rails renders its translation-missing text where
0.4.0 rendered English (`UPGRADING.md`). A `pt-BR` host that wants its own wording
overrides any key at any level of the chain above. Exception messages stay English.

### 16.7 Contract impact summary

- **Errors 8 → 12**, all `< TenancyDable::Error`: `CrossTenantReadError` (§16.1),
  `CrossTenantWriteError` (§16.2), `UnsafeIsolationError` (§16.4),
  `BypassReasonError` (§16.5). `ConfigurationError` is also raised by an invalid or
  repeated tenancy declaration (§16.3).
- **Settings 14 → 19:**

  | Setting | Default | `validate!` raises `ConfigurationError` unless |
  |---|---|---|
  | `guard_reads` | `true` | `true` or `false` |
  | `audit_ignored_namespaces` | `%w[ActiveStorage ActionText ActionMailbox SolidQueue SolidCache SolidCable]` | an Array of non-blank Strings or Symbols |
  | `audit_allowed` | `{}` | a Hash of non-blank String model names to non-blank String reasons |
  | `isolation_check` | `:raise` | `:raise`, `:warn` or `:off` |
  | `require_bypass_reason` | `false` | `true` or `false` |

  The install generator's initializer template lists the five, commented, with
  their defaults, like the other fourteen.
- **Facade (§3):** `without_tenant(reason: nil)`; new `snapshot`, `carry(&block)`,
  `audit(models = nil)`; new constant `WITHOUT_TENANT_EVENT`. The isolation check
  runs in every writer.
- **`Scoped` (§5.1):** `belongs_to_tenant(name = :tenant, tag: nil, **opts)`. Its
  step list gains step 0 (declare, §16.3) and step 7 (create refusal, §16.2).
- **`RelationExtension` (§5.2):** six read hooks, the `tenancy_pin_state`
  classifier, bulk-write behaviour unchanged.
- **New symbols:** `Declarations`, `Declaration`, `Audit`, `Audit::Finding`,
  `Audit::KINDS`, `Snapshot`; the `en` and `pt-BR` locale files; `rake tenancy_dable:audit`. Every
  Active Record class responds to `tenant_global`, `tenancy_declaration`,
  `tenancy_global_reason`, `tenancy_tag`.
- **§8 fixture schema, six tables:** adds `gadgets` (`tenant_id` NOT NULL and
  indexed via `t.references`, `name`, timestamps: a scoped model WITHOUT a
  uniqueness validation, so the create refusal is proven independent of
  validators) and `unindexed_records` (`tenant_id` bigint with NO index, `name`; no
  model file: the audit spec defines its throwaway models on it). Harness models:
  `Tenant` gains `has_many :widgets`, `has_one :first_widget, -> { order(:id) },
  class_name: "Widget"` and `has_many :gadgets`; `Widget` gains `has_many
  :children, class_name: "Widget", foreign_key: :parent_id, inverse_of: :parent`;
  new `Gadget` (`include TenancyDable::Scoped`, `belongs_to_tenant`); factory
  `:gadget`. The harness stays audit-clean.
- **§11 invariants:**

  | # | Invariant (amended) | Proven by (added) |
  |---|---|---|
  | 2 | **No cross-tenant read path** — filter-by-tenant before ordering; a read pinned to another tenant, or whose tenant filter was removed, raises `CrossTenantReadError`; bulk writes guarded; a create into another tenant raises `CrossTenantWriteError`; resolution enforces membership. True as of 0.5.0 within the residuals of §16.1. | `spec/scoping/read_guard_spec.rb`, `spec/scoping/create_refusal_spec.rb`, red-team fourth way (read through the tenant's own association) |
  | 6 | **No PII/secret leakage** — audit-override logs, gem exception messages and the `without_tenant` event carry tenant ids (the event also the host's reason and a `file:line`), never record payloads | `spec/facade/without_tenant_audit_spec.rb` (payload keys exactly three; no record on raise) |
  | 7 | **(new) No shared tenant state across fibers** — under a fiber scheduler with thread isolation, a tenant-state write raises `UnsafeIsolationError` (default `:raise`) | `spec/facade/isolation_check_spec.rb` |

- **Version** `0.5.0`, bumped at release.

### 16.8 Contract-spec delta (`spec/contract_spec.rb`)

Foundation writes every change below; where the behaviour lands in a workstream,
foundation lands the shape (§16.9) so the contract spec is green at the foundation
commit and stays green through every merge.

- Frozen defaults hash gains `guard_reads: true`, `isolation_check: :raise`,
  `require_bypass_reason: false`, `audit_allowed: {}`, `audit_ignored_namespaces:
  %w[ActiveStorage ActionText ActionMailbox SolidQueue SolidCache SolidCable]`.
- `"exposes exactly 14 settings"` → **19** (the comment updated: 14 at v0.4.0 plus
  the five of §16).
- Facade list gains `snapshot carry audit`. New: `without_tenant` parameters are
  exactly `[[:key, :reason]]`; `audit` parameters are `[[:opt, :models]]`;
  `WITHOUT_TENANT_EVENT == "without_tenant.tenancy_dable"`.
- `belongs_to_tenant`: the existing `[:opt, :name]` + `:keyrest` assertions stay;
  add `[:key, :tag]`.
- RelationExtension: public `pluck exists? ids load_async` in `instance_methods`;
  `exec_queries perform_calculation` in `private_instance_methods` and NOT in
  `instance_methods`; the three bulk overrides unchanged.
- Error hierarchy: title "8 subclasses" → "12 subclasses"; the list gains
  `CrossTenantReadError CrossTenantWriteError UnsafeIsolationError
  BypassReasonError`. `CrossTenantError::MESSAGE` lock unchanged; add
  `I18n.t("errors.messages.cross_tenant") == CrossTenantError::MESSAGE`, and that the
  locale files are in `I18n.load_path`, and `I18n.t("errors.messages.cross_tenant", locale: :"pt-BR")` is the `pt-BR` default.
- Declarations: `ActiveRecord::Base` responds to `tenant_global tenancy_declaration
  tenancy_global_reason tenancy_tag`; `tenant_global` parameters include
  `[:keyreq, :because]`, `[:key, :tag]`, `[:key, :allow_tenant_fk]`;
  `Declaration.members == %i[kind reason tag allow_tenant_fk]`.
- Audit: `Audit::KINDS == %i[undeclared global_with_tenant_fk scoped_without_index]`;
  `Audit::Finding.members == %i[model kind message]`; the rake file exists at
  `lib/tenancy_dable/tasks/audit.rake`.
- Snapshot: `Snapshot.members == %i[tenant membership tenant_scope_disabled]`; it
  defines `#restore`.

### 16.9 File-ownership map

**Shape first.** A serial FOUNDATION commit lands every shared edit and the whole
public shape (constants, classes, signatures, call sites), with stub bodies that
keep 0.4.0 behaviour. Four PARALLEL workstreams, one git worktree each cut from
that commit, then fill in behaviour and prove it. During the parallel stage
**every file has exactly one owner**; a workstream edits only the files listed
under it and creates only the spec files listed under it. Nobody in the parallel
stage edits `lib/tenancy_dable/version.rb` (bumped at release), `README.md`,
`UPGRADING.md` or `CHANGELOG.md` (the docs phase), `spec/support/**`,
`spec/rails_helper.rb`, `spec/spec_helper.rb` or `spec/internal/**`.

**FOUNDATION (serial).**

| File | Change | Final, or owner afterwards |
|---|---|---|
| `lib/tenancy_dable/errors.rb` | the four new classes (§16.7) | final |
| `lib/tenancy_dable/configuration.rb` | five settings, defaults, `validate!` rules (§16.7) | final |
| `lib/tenancy_dable/locale/en.yml`, `pt-BR.yml` | new (§16.6) | final |
| `lib/tenancy_dable/railtie.rb` | `initializer "tenancy_dable.i18n"`; `rake_tasks { load ... }`; in `install_active_record!`, `require "tenancy_dable/declarations"` and `ActiveRecord::Base.extend(TenancyDable::Declarations)` BEFORE the identity concerns are required | final |
| `lib/tenancy_dable/models/tenant_model.rb`, `membership_model.rb`, `user_model.rb` | the three declarations (§16.3; they reach the stub until W2 lands) and the two i18n swaps (§16.6) | final |
| `lib/tenancy_dable/scoped.rb` | `belongs_to_tenant(name = :tenant, tag: nil, **opts)` whose first statement is `tenancy_declare!(:scoped, tag: tag)`; `errors.add(reflection.name, :cross_tenant)` | W3 |
| `lib/tenancy_dable/relation_extension.rb` | the six read hooks (§16.1, right visibility), each calling a private `tenancy_guard_read!` stub that returns `nil` | W1 |
| `lib/tenancy_dable/declarations.rb` | new: `Declaration` (final); `Declarations` with final signatures; `tenant_global` calls `tenancy_declare!(:global, reason: because, tag:, allow_tenant_fk:)`; stub `tenancy_declare!` stores nothing and returns `nil`; readers return `nil` | W2 |
| `lib/tenancy_dable/audit.rb` | new: `KINDS`, `Finding` (final); stub `run` returns `[].freeze` | W2 |
| `lib/tenancy_dable/tasks/audit.rake` | new, final body (§16.3) | W2 |
| `lib/tenancy_dable/snapshot.rb` | new: `Snapshot` with final members; stub `restore` yields without touching state | W4 |
| `lib/tenancy_dable.rb` | `require "tenancy_dable/snapshot"`, `require "tenancy_dable/audit"`; `WITHOUT_TENANT_EVENT`; `without_tenant(reason: nil)` (signature only); `snapshot`, `carry`, `audit` (final, §16.3/§16.4) | W4 |
| `lib/generators/tenancy_dable/install/templates/initializer.rb.tt` | the five settings, commented with defaults | final |
| `tenancy_dable.gemspec` | `spec.add_development_dependency "async", "~> 2.0"` | final |
| `spec/contract_spec.rb` | §16.8 | final |
| `spec/configuration_spec.rb` | `validate!` for the five settings: each default accepted, one bad value each rejected with `ConfigurationError` naming the setting | final |
| `spec/internal/db/schema.rb`, `spec/internal/app/models/{tenant,widget}.rb`, new `spec/internal/app/models/gadget.rb`, `spec/support/factories.rb` | §16.7 fixtures (`gadgets`, `unindexed_records`, the associations, `Gadget`, `:gadget`) | final |
| `spec/schema_spec.rb` | six tables; `gadgets.tenant_id` indexed; `unindexed_records.tenant_id` has no index | final |

Foundation gate: the whole suite green (the existing 293 plus the new
contract/config/schema examples), `standardrb` clean, and no behaviour change yet:
the i18n swaps keep every English string, and every stub is inert.

**W1 - read guard** (§16.1).

- Owns: `lib/tenancy_dable/relation_extension.rb` (the `tenancy_guard_read!` body,
  the `tenancy_pin_state` classifier, the bulk-write guard rewritten on it with
  unchanged messages), `spec/security/red_team_spec.rb`,
  `spec/scoping/bulk_write_guard_spec.rb`.
- Creates: `spec/scoping/read_guard_spec.rb`: every leaking shape of §16.1 raises
  `CrossTenantReadError` naming the model; `ids`, `has_one`, `unscope(where:
  :tenant_id)`, `unscope(where: "widgets.tenant_id")`, `unscope(:where)`, `or(a.widgets)`
  and `load_async` each in their own example; `a.widgets.destroy_all` refused with A's
  rows intact; the pass-through cases (`rewhere(tenant_id: current)`,
  `unscope(where: :tenant_id).where(tenant_id: current)`, `unscope(where: :name)`,
  `unscoped.where(id:).pick(:tenant_id)`, `b.widgets`, a preload of the current
  tenant, `widget.children`, `reload`, `without_tenant { a.widgets.to_a }`); a
  non-scoped model untouched; `guard_reads = false` restores the 0.4.0 answers.
- Flips: `spec/security/red_team_spec.rb:48` (the assertion at line 56,
  `Widget.where(tenant_id: tenant_b.id).to_a` empty → raises
  `CrossTenantReadError`); the describe "three ways" gains a fourth (a read
  through the tenant's own association).
- Must not touch: `scoped.rb` (the gem's `unscoped.where(id:).pick(fk)` passes as
  `:unpinned`, so it needs no change).

**W2 - declarations, audit, rake** (§16.3).

- Owns: `lib/tenancy_dable/declarations.rb`, `lib/tenancy_dable/audit.rb`,
  `lib/tenancy_dable/tasks/audit.rake`.
- Creates: `spec/declarations/declarations_spec.rb` (reason required and blank
  refused; tag and `allow_tenant_fk` validated; the readers; no re-declaration
  either way, inherited included; `tag:` not forwarded to `belongs_to`; the
  identity concerns declared), `spec/declarations/audit_spec.rb` (each finding
  kind; ignored namespaces; `audit_allowed`; abstract, STI, anonymous and stale
  classes skipped; a composite index and a leading composite primary key count;
  explicit `models` not eager-loaded; the harness is audit-clean with no argument),
  `spec/declarations/audit_task_spec.rb` (exit status `1` with findings on stderr,
  `0` when clean; load the tasks once with `Rails.application.load_tasks` unless
  `Rake::Task.task_defined?("tenancy_dable:audit")`, `reenable` between
  invocations, and assert `SystemExit#status`). Throwaway models are named with
  `stub_const` and built on `widgets`/`unindexed_records`.
- Flips: none.
- Must not touch: `scoped.rb` and the identity concerns (foundation already wrote
  their call sites); a needed change there goes back to the orchestrator.

**W3 - create refusal + i18n proofs** (§16.2, §16.6).

- Owns: `lib/tenancy_dable/scoped.rb` (the two prepended callbacks and
  `tenancy_refuse_foreign_tenant!`), `spec/scoping/tenant_assignment_spec.rb`,
  `spec/scoping/cross_tenant_spec.rb`.
- Creates: `spec/scoping/create_refusal_spec.rb` (`a.widgets.create!`,
  `Widget.create!(tenant: a)`, `Gadget.create!(tenant_id: a.id)` with no
  uniqueness validation, `save(validate: false)`, and `valid?` all raise
  `CrossTenantWriteError` (never `CrossTenantReadError`) with no row written; the
  current tenant's explicit FK, a blank FK, no current tenant and `without_tenant`
  all persist as in 0.4.0), `spec/i18n/messages_spec.rb` (each key renders its
  English default; a host override wins at the model-attribute level and at
  `errors.messages`; `errors.details` carries `:cross_tenant`/`:last_owner`;
  translations stored by an example are removed afterwards).
- Flips: `spec/scoping/tenant_assignment_spec.rb:19` (§16.2).
- Must not touch: the `tenancy_declare!` line and the `belongs_to_tenant`
  signature (foundation's, used by W2).

**W4 - facade: fiber safety + audited bypass** (§16.4, §16.5).

- Owns: `lib/tenancy_dable.rb` (`check_isolation!`, the private
  `tenant_scope_disabled` writer, the reason check, the event and `call_site`),
  `lib/tenancy_dable/snapshot.rb` (`restore`), `spec/tenancy_dable_spec.rb`.
- Creates: `spec/facade/isolation_check_spec.rb` (three modes on every writer,
  stubbed; one real `Async` reactor with thread vs `:fiber` isolation),
  `spec/facade/snapshot_spec.rb` (raw state captured; restore across `Thread.new`
  and an `Async` task; reset after restore on exit and on raise; RLS fires through
  `current_tenant=`; carried foreign membership answers nil; `carry` forwards
  arguments), `spec/facade/without_tenant_audit_spec.rb` (event fires with exactly
  the three keys; `call_site` points at the spec file; blank reason raises only when
  required, with no event and no state change; nested bypasses report each level
  and restore on normal exit and on raise; no record in the payload when the block
  raises).
- Flips: none.
- Must not touch: `relation_extension.rb` and `scoped.rb` (they read
  `Current.tenant_scope_disabled`, whose meaning does not change).

**Merge order and the integration gate.** Any order merges cleanly, because no two
workstreams share a file. After all four: the full suite green on the default
bundle, the two flipped specs asserting their new contract, and the prototype
measurements of §16.1/§16.2 reproduced by `read_guard_spec.rb` and
`create_refusal_spec.rb` (the read guard and the create refusal meet in one
example: `Widget`, which has a uniqueness validation, raises
`CrossTenantWriteError`, not `CrossTenantReadError`).
