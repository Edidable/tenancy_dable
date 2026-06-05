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

Additive seams reserved by this design (beyond the frozen file list — see §10):

| Symbol | File | Implemented in |
|---|---|---|
| `TenancyDable::Job` (ActiveJob tenant propagation) | `lib/tenancy_dable/job.rb` | 13 |

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
    def current_membership                   #=> membership instance | nil
    def current_membership=(membership)
    def with_tenant(tenant) { ... }          # set tenant for block; ensure-restore
    def without_tenant { ... }               # set tenant_scope_disabled; ensure-restore

    # --- authorization builder (additive, introduced Phase 06; §6) -------
    def pundit_context(user:, tenant:, membership:)  #=> Policy::Context
  end
end
```

Return-shape contract:
- `current_tenant` / `current_membership` return the live AR instances stored in
  `Current`, or `nil`.
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
