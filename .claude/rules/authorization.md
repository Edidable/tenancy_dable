---
paths:
  - "lib/tenancy_dable/policy/**"
  - "spec/policy/**"
---
A policy decides on `Policy::Context` (user + tenant + membership), never a bare user; build it with `TenancyDable.pundit_context`. Proof: `spec/policy/context_spec.rb`.
`Policy::Context` stays a frozen `Data` type with no Active Record dependency; the entry file requires it at load time. `spec/contract_spec.rb` locks it.
Every action on `Policy::Base` returns false; `new?` delegates to `create?` and `edit?` to `update?`. Do not make any default action true. Proof: `spec/policy/secure_by_default_spec.rb`.
`Base::Scope#resolve` returns `scope.none` without a tenant and filters by `configuration.tenant_fk` with one. Never fall back to `scope.all`. Proof: `spec/policy/scope_spec.rb`.
The context readers and the capability helpers (`owner?`, `manager?`, `member?`, `same_tenant?`) stay private, or Pundit introspection and matchers read them as actions.
`same_tenant?` must stay safe on a record without `tenant_id` (false, no raise); with no context tenant it is false for a record that carries a tenant id and true when the record's `tenant_id` is also nil, so a policy also checks `member?`. Proof: `spec/policy/same_tenant_spec.rb`.
`owner?` is `roles.first` and `manager?` is `configuration.manager_role?`; never hard-code owner/admin/member. Proof: `spec/policy/capability_matrix_spec.rb`.
Collection actions have no record-tenant gate; a policy on a record must call `same_tenant?` itself. Proof: `spec/policy/concrete_policy_spec.rb`.
Do not `require "pundit"` or include Pundit in the policy classes; the only gem require is the lazy one in the controller's `:not_authorized` branch.
The policy layer never reads the facade; it sees only the context it is handed.
If you change the base policy or scope shape, also update `lib/generators/tenancy_dable/install/templates/application_policy.rb.tt` (the `Context` alias and `Scope` subclass), `spec/generators/install_generator_spec.rb`, `README.md` and `spec/contract_spec.rb`.
Narrative: docs/domains/authorization.md
