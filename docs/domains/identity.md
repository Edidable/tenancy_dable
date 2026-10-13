# Identity models

## Overview

Three concerns give a host its identity graph: a user is a global identity that joins one or more tenants through a membership, and each membership carries a role. [FILE:lib/tenancy_dable/models/tenant_model.rb], [FILE:lib/tenancy_dable/models/user_model.rb] and [FILE:lib/tenancy_dable/models/membership_model.rb] define [CLASS:TenancyDable::TenantModel], [CLASS:TenancyDable::UserModel] and [CLASS:TenancyDable::MembershipModel]. A host mixes each into its own model with `include`; the railtie makes the files available when Active Record loads, and the contract is `DESIGN.md` §6.

The model names are read from configuration (`config.tenant_model`, `config.user_model`, `config.membership_model`), so a host that renames its models still gets a correctly wired graph. The settings are documented in [REF:configuration.md].

## Principles

[RULE:the identity models are global, declared by the concern] Each concern calls `tenant_global` with a built-in reason when it is included, so the host writes no declaration line and the audit finds all three declared ([SPEC:spec/declarations/declarations_spec.rb] "the identity concerns"). The declaration mechanics are in [REF:declarations.md].

[RULE:Membership is not tenant-scoped] `MembershipModel` deliberately does not include `TenancyDable::Scoped`. Membership is the table consulted to learn which tenants a user belongs to: slug resolution and `User#membership_for` read it before any tenant is current, so a fail-closed default scope on it would raise `NoTenantError` during resolution and deadlock the request. It is declared global with `allow_tenant_fk: true` because it carries a tenant column on purpose. [SPEC:spec/identity/membership_not_scoped_spec.rb] proves it does not declare itself scoped, is queryable with no current tenant, does not fail closed when `require_tenant` is active, and ignores a current tenant entirely.

## TenantModel

[ASSOC:TenantModel] wires `has_many :memberships` (class from `config.membership_model`, `dependent: :destroy`) and `has_many :users, through: :memberships`. Destroying a tenant destroys its memberships.

[RULE:every tenant has a unique, URL-safe slug] The slug is the key slug resolution looks up. It must be present and unique, and its format must match [CONST:TenantModel::SLUG_FORMAT]: lowercase alphanumerics joined by single hyphens, with no leading or trailing hyphen. The format check is skipped for a blank value so `presence` owns the missing-slug message and the two do not both fire; a bad format carries the `:slug_format` message key ([SPEC:spec/identity/tenant_model_spec.rb] "slug validations").

[RULE:a slug is generated only when none is given] A `before_validation` callback derives the slug from `name` when the slug is blank, transliterates accents (`parameterize`), folds punctuation to hyphens, folds underscores to hyphens (`parameterize` alone keeps them), collapses repeats and trims the edges, so the result always matches the format. A taken slug gets a numeric suffix: `base`, `base-2`, `base-3`, and so on. An explicitly supplied slug is never rewritten, though its format is still validated. `name` is a convenience column and not part of the contract: a tenant model without it must supply the slug itself, and `presence` reports a missing one ([SPEC:spec/identity/tenant_model_spec.rb] "slug auto-generation"). The unique database index on the slug column is the guard against the check-then-insert race; the generator's migration creates it.

[METHOD:Tenant#owners] answers a relation of the user records who hold the owner role in this tenant, built as a subquery over the tenant's memberships, so it composes with further scopes and follows a renamed membership or user model. It excludes owners of other tenants and is empty for a tenant with no owner ([SPEC:spec/identity/tenant_model_spec.rb] "#owners").

## UserModel

[ASSOC:UserModel] wires `has_many :memberships` (`dependent: :destroy`) and `has_many :tenants, through: :memberships`.

[METHOD:User#membership_for(tenant)] answers this user's membership in the tenant, found by tenant id so the tenant need not be reloaded, and nil for a nil tenant or a non-member. It reads only the receiver's own memberships, never another user's. [METHOD:User#member_of?(tenant)] is true when that lookup finds a membership and false for a nil tenant ([SPEC:spec/identity/user_membership_spec.rb]).

## MembershipModel

[ASSOC:MembershipModel] wires `belongs_to :user` and `belongs_to :tenant` with the configured class names.

[RULE:roles come from configuration] `config.roles` is ordered highest first. The role must be included in that list, checked at validation time through a callable, so a reconfigured role set is honored without reloading the model ([SPEC:spec/identity/membership_validations_spec.rb] "role inclusion"). A user holds at most one membership per tenant: `user_id` is unique within `tenant_id` ([SPEC:spec/identity/membership_validations_spec.rb] "[user_id, tenant_id] uniqueness").

[RULE:one predicate per configured role] Role predicates (`owner?`, `admin?`, `member?` by default) are generated from `config.roles` when the concern is included, so a host must configure its roles in an initializer, before its models load. [SPEC:spec/identity/membership_roles_spec.rb] proves one predicate per role and that the set follows the config rather than a hard-coded list.

[RULE:owners and admins are scopes over the configured roles] `Membership.owners` filters on the single highest role, `config.roles.first`; `Membership.admins` filters on `config.manager_roles`. Both read the config at call time. `Tenant#owners` is different: it answers the user records, not the memberships.

[METHOD:Membership#manager?] is true when the membership's role is in `config.manager_roles` and tracks a reconfigured set ([SPEC:spec/identity/membership_roles_spec.rb] "#manager?").

### The last-owner guard

[RULE:a tenant never loses its only owner by demotion] A `before_update` callback refuses a role change from the owner role (`config.roles.first`) to any other role when no other owner of the same tenant exists. It adds the `:last_owner` error on `role` and halts the save with `throw :abort`: `update` answers false, `update!` raises `ActiveRecord::RecordNotSaved`, and the row is unchanged. Demoting one of several owners succeeds; the check looks only at the membership's own tenant; editing a non-owner membership and promoting a member are untouched ([SPEC:spec/identity/last_owner_guard_spec.rb]).

[ABSENCE:the guard covers demotion only] It is a `before_update`, so destroying the last owner's membership is not stopped by it, and destroying a tenant removes its memberships through the `dependent: :destroy` association. A host that wants removal blocked adds the check in its policy layer.

## Gotchas

### Gotcha: Roles configured after the models load

[SYMPTOM:`membership.owner?` or a custom role's predicate raises `NoMethodError`, or a role added in an initializer has no predicate]. [CAUSE:predicates are defined once, when `MembershipModel` is included, from the roles configured at that moment]. [FIX:call `TenancyDable.configure` in an initializer, which runs before the host's models load; a spec that changes roles later gets the validation and scopes but not new predicates]. [RULE:configure roles before the membership model loads].

### Gotcha: The membership table's tenant column is always `tenant_id`

[SYMPTOM:with `config.tenant_fk` set to another name, the membership uniqueness check, the last-owner lookup and `User#membership_for` still use `tenant_id`, and so do `TenancyDable.current_membership` and `Policy::Base#same_tenant?`]. [CAUSE:`MembershipModel` scopes its `user_id` uniqueness and its other-owners query by the literal `tenant_id` column of the membership table, `UserModel#membership_for` finds by `tenant_id`, and the facade's `current_membership` compares the membership's `tenant_id`, none of them through the setting, which names the column on tenant-scoped models; the install generator's membership migration creates `tenant_id`]. [FIX:keep the membership table's column named `tenant_id`]. [RULE:the uniqueness scope, the last-owner query, `User#membership_for` and `current_membership` read that literal column].

## Related

Why the lookups run before any tenant exists: [REF:resolution.md]. Declarations: [REF:declarations.md]. Settings: [REF:configuration.md]. The i18n key for `:last_owner` and `:slug_format`: [REF:i18n.md].
