---
paths:
  - "lib/tenancy_dable/models/**"
  - "spec/identity/**"
---
`TenantModel`, `UserModel`, `MembershipModel` are included by the host; each calls `tenant_global` itself. Never add a second declaration on a model that includes one (`spec/declarations/declarations_spec.rb` "the identity concerns").
`MembershipModel` must NOT include `Scoped`: it is read before any tenant is current, and a fail-closed scope would deadlock resolution. `spec/identity/membership_not_scoped_spec.rb` is the gate.
Membership is declared `allow_tenant_fk: true`; keep its table column named `tenant_id`, because the uniqueness scope, the last-owner query, `User#membership_for` and `current_membership` read that literal column.
The owner role is `config.roles.first`; `owners` scopes on it, `admins` and `manager?` on `config.manager_roles`. Read config at call time in lambdas and the role inclusion check.
Role predicates are generated from `config.roles` at include time; do not hard-code role names, and configure roles before the models load.
Last-owner guard: `before_update`, adds `:last_owner` on `role`, `throw :abort`. It covers demotion only, not destroy. `spec/identity/last_owner_guard_spec.rb`.
`Tenant#owners` returns users (subquery over memberships); `Membership.owners` returns memberships. Do not conflate them.
Slugs: present, unique, `SLUG_FORMAT`; generated from `name` only when blank, folding `_` to `-`, suffixed `-2`, `-3` on collision; never rewrite a supplied slug. The format check skips blank values.
Association class names come from `config.*_model`; keep them out of literals.
If you change a validation or an error key, also change the locale files (`:last_owner`, `:slug_format`) and the matching spec.
Narrative: docs/domains/identity.md
