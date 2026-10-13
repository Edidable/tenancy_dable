# Authorization

Authorization is a Pundit layer that decides on a user, a tenant and a membership together, with every action denied until a concrete policy grants it. The code is [FILE:lib/tenancy_dable/policy/context.rb] and [FILE:lib/tenancy_dable/policy/base.rb]; the specs are under [FILE:spec/policy/].

## Overview

The pieces are a value object, a base policy with a nested scope, and the facade builder that makes the value object:

- [CLASS:TenancyDable::Policy::Context] is a frozen [CLASS:Data] type with the members [FIELD:user], [FIELD:tenant] and [FIELD:membership], and one derived reader, [METHOD:role], which is the membership's role or nil. It has no Active Record dependency, which is why the entry file requires it at load time. [SPEC:spec/policy/context_spec.rb] proves the role derivation, a nil role without a membership, and that [METHOD:TenancyDable.pundit_context] builds the same triple as [METHOD:Context.new]; [SPEC:spec/contract_spec.rb] locks the type as a [CLASS:Data].
- [METHOD:TenancyDable.pundit_context(user:, tenant:, membership:)] builds the context. The host returns it from its Pundit user hook, so [METHOD:authorize] and [METHOD:policy_scope] decide on the triple.
- [CLASS:TenancyDable::Policy::Base] takes the context and a record. [CLASS:TenancyDable::Policy::Base::Scope] takes the context and a relation.
- The install generator writes an [CLASS:ApplicationPolicy] that subclasses the base, aliases [CONST:Context], and subclasses the base scope (see `docs/domains/generators.md`).

## Principles

[RULE:A policy decides on a context, never a bare user]. The same user is an owner in one tenant and a non-member in another, so identity alone cannot answer whether an action is allowed; the acting role comes from the membership in the acting tenant.

[RULE:Every action denies by default]. [METHOD:index?], [METHOD:show?], [METHOD:create?], [METHOD:update?] and [METHOD:destroy?] return false until a subclass overrides them, so forgetting to define an action denies instead of leaking. [METHOD:new?] delegates to [METHOD:create?] and [METHOD:edit?] delegates to [METHOD:update?], so granting a write grants its form and denying the write keeps the form closed. [SPEC:spec/policy/secure_by_default_spec.rb] proves the denials, including for an owner of the record's tenant, and the two delegations in both directions.

[RULE:The scope fails closed]. [METHOD:Base::Scope#resolve] returns [METHOD:scope.none] when the context has no tenant and otherwise filters the scope by the configured [CONFIG:tenant_fk] equal to the tenant's id. A concrete [CONST:WidgetPolicy::Scope] inherits it through constant lookup. [SPEC:spec/policy/scope_spec.rb] proves the empty result without a tenant, the filter, and the exclusion of other tenants' rows.

## Helpers

The context readers ([METHOD:user], [METHOD:tenant], [METHOD:membership], [METHOD:role]) and the capability helpers are private on the base policy, so Pundit's action introspection and policy matchers never mistake them for policy actions. A concrete policy calls them from its own action methods.

- [METHOD:same_tenant?] is true when the record responds to [METHOD:tenant_id] and its value equals the context tenant's id. It is false for another tenant's record and false without raising on a record that carries no [METHOD:tenant_id], so any policy can call it unconditionally. With no context tenant it is false for a record that carries a tenant id and true when the record's `tenant_id` is also nil (the comparison is `nil == nil`), so a policy also checks [METHOD:member?]. It compares the literal [METHOD:tenant_id] attribute, not the configured [CONFIG:tenant_fk]. [SPEC:spec/policy/same_tenant_spec.rb] proves the same-tenant, other-tenant and no-`tenant_id` cases; no example covers a nil context tenant with a nil record tenant.
- [METHOD:owner?] is true when the role equals the first entry of [CONFIG:roles]; the top role is the owner by position, not by name.
- [METHOD:manager?] asks the configuration whether the role is in [CONFIG:manager_roles].
- [METHOD:member?] is true when a role is present.

[SPEC:spec/policy/capability_matrix_spec.rb] proves the predicates for every configured role and that the matrix is derived from configuration instead of from the names owner, admin and member. [SPEC:spec/policy/concrete_policy_spec.rb] proves the conventional composition: reads require [METHOD:member?], writes require [METHOD:manager?], record-bearing actions also require [METHOD:same_tenant?], so a manager of one tenant cannot touch a row of another, and a non-member can do nothing.

## Boundaries

[RULE:Same-tenant is an explicit check]. The base policy does not apply [METHOD:same_tenant?] for the policy author; collection actions such as [METHOD:index?] and [METHOD:create?] have no record-tenant gate by design, and a policy that guards a record must call it.

[RULE:Pundit is a runtime dependency but is not required by the policy classes]. The base policy does not include or require Pundit; Pundit calls its methods by convention. The only gem code that requires Pundit is the controller's [VALUE:not_authorized] branch, lazily (see `docs/domains/resolution.md`).

[ABSENCE:The policy layer does not read the facade]. A policy sees only the context it is handed, so a test builds a context by hand and never needs a current tenant.

## Gotchas

### Gotcha: Hosts that do not wire the Pundit user hook

[SYMPTOM:a policy helper such as `manager?` or `same_tenant?` raises NoMethodError for role or tenant on a user object]. [CAUSE:the base policy expects a context, and a bare user has no tenant or membership]. [FIX:return the result of `TenancyDable.pundit_context` from the controller's `pundit_user`]. [RULE:every policy and scope call goes through the context; the generated ApplicationPolicy documents the hook].
