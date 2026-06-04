# TenancyDable — Build Plan & Frozen Contract

> **This file is authoritative.** Every phase worker reads it first and honors the
> contract below **exactly** — names, signatures, file paths, and security
> invariants are frozen. If a phase needs to deviate, it must record the reason
> in `DESIGN.md` and keep the public surface unchanged. There are no human review
> gates (fully autonomous run), so this document is the contract.

## Mission

`tenancy_dable` is the multi-workspace tenancy layer for the **edidable** Rails
SaaS skeleton family, shipped as one versioned gem so derived projects inherit
the same isolation guarantees and update via `bundle update`. It is **not** a
bare row-scoper — it bundles scoping + identity (memberships/roles) + slug
resolution + Pundit authorization.

## Decisions (frozen)

- **Self-contained scoping engine.** No `acts_as_tenant` / `rails-tenantify`
  dependency. Own the ~150-line core. Reference their patterns, don't import them.
- **Runtime deps:** `activesupport`, `activerecord`, `actionpack`, `railties`
  (>= 7.1, < 9), `pundit` (>= 2.3). Ruby >= 3.2.
- **Test harness:** Combustion + sqlite3 + RSpec. Lint: Standard.
- **Git:** `sequential-branch`. One worker per phase, **strictly sequential, no
  concurrent writers on the branch** (correctness over speed for a foundation).
- **Each phase verifies its dependencies are on disk before doing work** (guards
  against out-of-order execution).

## Frozen public contract

### Namespace & file layout
```
lib/tenancy_dable.rb                      # entry + .configure/.configuration/.current_* facade
lib/tenancy_dable/version.rb
lib/tenancy_dable/configuration.rb
lib/tenancy_dable/current.rb              # ActiveSupport::CurrentAttributes
lib/tenancy_dable/errors.rb
lib/tenancy_dable/railtie.rb
lib/tenancy_dable/scoped.rb               # belongs_to_tenant model concern
lib/tenancy_dable/relation_extension.rb   # bulk-write guard (prepended to AR::Relation)
lib/tenancy_dable/models/tenant_model.rb
lib/tenancy_dable/models/membership_model.rb
lib/tenancy_dable/models/user_model.rb
lib/tenancy_dable/controller/resolvable.rb
lib/tenancy_dable/policy/context.rb
lib/tenancy_dable/policy/base.rb
lib/generators/tenancy_dable/install/install_generator.rb (+ templates/)
lib/generators/tenancy_dable/model/model_generator.rb    (+ templates/)
```

### Configuration — `TenancyDable.configure { |c| ... }`
| Setting | Default | Meaning |
|---|---|---|
| `tenant_model` | `"Tenant"` | workspace model name |
| `user_model` | `"User"` | global identity model name |
| `membership_model` | `"Membership"` | join model name |
| `roles` | `%w[owner admin member]` | ordered, highest-first; predicates generated from this |
| `manager_roles` | `%w[owner admin]` | the "can manage workspace" set |
| `tenant_fk` | `:tenant_id` | foreign key on scoped models |
| `slug_param` | `:tenant_slug` | URL param for resolution |
| `require_tenant` | `false` | bool or callable; when truthy in current ctx, an unscoped query on a scoped model raises `NoTenantError` (fail-closed) |
| `rls` | `false` | when true, fire `rls_statement` on tenant change |
| `rls_statement` | `->(t){ "SET app.tenant_id = #{quote(t&.id)}" }` | SQL emitted on tenant change |
| `audit_overrides` | `:log` | `:log`/`:raise`/`:ignore` when current_tenant is reassigned to a different tenant |
| `on_tenant_not_found` | `:raise` | `:raise` (RecordNotFound) / `:null` |
| `current_user_resolver` | `-> { defined?(Current) && Current.respond_to?(:user) ? Current.user : nil }` | how Resolvable finds the acting user (auth-agnostic) |

### `TenancyDable::Current < ActiveSupport::CurrentAttributes`
- `attribute :tenant, :membership, :tenant_scope_disabled`
- Facade on `TenancyDable`: `.current_tenant`, `.current_tenant=` (runs audit-override check + RLS hook), `.current_membership`, `.current_membership=`, `.with_tenant(t){}`, `.without_tenant{}` (sets `tenant_scope_disabled`).

### `TenancyDable::Scoped` (model concern)
- `belongs_to_tenant(name = :tenant, **opts)`:
  - `belongs_to name` (+ opts), class predicate `tenant_scoped?` → true.
  - `default_scope`: if `tenant_scope_disabled` → `all`; elsif `current_tenant` → `where(fk => current_tenant.id)`; elsif `require_tenant` truthy → **raise `NoTenantError`**; else `all`.
  - `before_validation on: :create` → auto-assign fk from `current_tenant` when blank.
  - tenant fk **immutable**: reassigning a persisted record's fk raises `TenantImmutableError`.
  - cross-tenant `belongs_to` validation: a referenced tenant-scoped association from another tenant adds error `CrossTenantError`-style message.
  - `validates_uniqueness_to_tenant(*fields, **opts)` helper (scopes uniqueness by fk).
- `RelationExtension` prepended to `ActiveRecord::Relation`: `update_all`/`delete_all`/`destroy_all` raise `BulkWriteError` when the relation's model is tenant-scoped and there is no active tenant **or** the relation isn't scoped to the current tenant; bypass via `TenancyDable.without_tenant`.

### Identity concerns
- `TenancyDable::TenantModel` → `has_many :memberships, dependent: :destroy`, `has_many :users, through: :memberships`; slug presence+uniqueness+format, `before_validation` slug generation w/ collision suffix; `#owners`.
- `TenancyDable::MembershipModel` → `belongs_to :user, :tenant`; `validates :role, inclusion: roles`; `validates :user_id, uniqueness: {scope: :tenant_id}`; role predicates from config (`owner?`…); scopes `owners`/`admins(manager_roles)`; `before_update` last-owner-demotion guard (`throw :abort`); `#manager?`. **Does NOT include `Scoped`** (queried before tenant is known) — must be documented inline.
- `TenancyDable::UserModel` → `has_many :memberships, dependent: :destroy`, `has_many :tenants, through:`; `#membership_for(tenant)`, `#member_of?(tenant)`.

### `TenancyDable::Controller::Resolvable` (controller concern)
- class macro `resolve_tenant!(**before_action_opts)` installs a before_action that:
  1. finds tenant via `tenant_model.find_by!(slug: params[slug_param])` (honor `on_tenant_not_found`),
  2. resolves acting user via `current_user_resolver`,
  3. requires membership (`user.membership_for(tenant)`) else raise `NotAMemberError`,
  4. sets `TenancyDable.current_tenant` + `current_membership`.
- `default_url_options` merges `{ slug_param => current_tenant&.slug }`.
- Never trusts an id from the URL — slug only.

### Authorization
- `TenancyDable::Policy::Context = Data.define(:user, :tenant, :membership)` with `#role`.
- `TenancyDable::Policy::Base`: secure-by-default (`index?/show?/create?/update?/destroy?` → false); helpers `same_tenant?` (`record.tenant_id == tenant&.id`), `owner?`, `manager?` (role in manager_roles), `member?` (role present); nested `Scope` whose `resolve` returns `scope.none` when tenant nil else `scope.where(tenant_fk => tenant.id)`.

### Errors (all < `TenancyDable::Error`)
`NoTenantError`, `TenantImmutableError`, `BulkWriteError`, `CrossTenantError`, `NotAMemberError`, `TenantNotFoundError`, `TenantOverrideError`, `ConfigurationError`.

### Generators
- `tenancy_dable:install` → initializer, migrations (`tenants`, `memberships`), `app/policies/application_policy.rb < TenancyDable::Policy::Base`, a `Current` attributes patch or instructions, route-scaffold comment, and (if models exist) instructions to include the identity concerns; idempotent.
- `tenancy_dable:model NAME field:type…` → tenant-scoped model including `Scoped` + migration with `tenant_id` + index.

## Security invariants (audited in Phase 15)
1. **Fail-closed when configured:** with `require_tenant` active, an unscoped query on a scoped model raises — never silently returns all tenants' rows.
2. **No cross-tenant read path:** filter by tenant before any ordering; bulk-writes guarded; resolution enforces membership.
3. **`tenant_id` immutable** after create.
4. **Pundit scope fails closed** (`scope.none`) with no active tenant.
5. **Slug-only resolution:** never trust a tenant id from the URL.
6. **No PII/secret leakage:** audit logs carry tenant ids only, never payloads.

## Phase index
| # | Phase | Spec | Validates |
|---|---|---|---|
| 00 | Contract freeze → `DESIGN.md` | `phases/00-contract-freeze.md` | doc exists |
| 01 | Test harness (Combustion) | `phases/01-test-harness.md` | `bundle exec rspec` |
| 02 | Configuration + Current | `phases/02-configuration-current.md` | standardrb + rspec |
| 03 | Scoping engine | `phases/03-scoping-engine.md` | standardrb |
| 04 | Identity concerns | `phases/04-identity-models.md` | standardrb |
| 05 | Slug resolution | `phases/05-resolution-controller.md` | standardrb |
| 06 | Authorization (Pundit) | `phases/06-authorization-pundit.md` | standardrb |
| 07 | Generators | `phases/07-generators.md` | standardrb |
| 08 | Specs: scoping | `phases/08-specs-scoping.md` | rspec spec/scoping |
| 09 | Specs: identity/roles | `phases/09-specs-identity.md` | rspec spec/identity |
| 10 | Specs: resolution | `phases/10-specs-resolution.md` | rspec spec/resolution |
| 11 | Specs: authorization | `phases/11-specs-authorization.md` | rspec spec/policy |
| 12 | Specs: generators | `phases/12-specs-generators.md` | rspec spec/generators |
| 13 | Integration spec | `phases/13-integration.md` | rspec spec/integration |
| 14 | Docs (README/UPGRADING) | `phases/14-docs.md` | markdown present |
| 15 | Critic / hardening | `phases/15-critic-hardening.md` | `bundle exec rake` + audit |
