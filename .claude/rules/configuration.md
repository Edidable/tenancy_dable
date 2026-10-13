---
paths:
  - "lib/tenancy_dable/configuration.rb"
  - "spec/configuration_spec.rb"
---
All validation lives in `Configuration#validate!`, called by `TenancyDable.configure` after the block; no consumer re-validates. It raises `ConfigurationError` naming the setting.
`validate!` rules: `roles` non-empty; `manager_roles` a subset of `roles`; model names non-blank; `on_not_a_member` not an unknown Symbol (any non-Symbol passes and fails at request time); `guard_reads` and `require_bypass_reason` booleans; `isolation_check` one of `:raise :warn :off`; `audit_ignored_namespaces` an Array of non-blank String or Symbol; `audit_allowed` a Hash of non-blank String to non-blank String.
Unchecked on purpose: `tenant_fk`, `slug_param`, `require_tenant`, `rls`, `rls_statement`, `audit_overrides`, `on_tenant_not_found`, `current_user_resolver`.
Defaults are contract: `spec/contract_spec.rb` asserts each and derives the setting set from the class's writers, so a new `attr_accessor` fails it until updated.
Mutable defaults (`audit_ignored_namespaces`, `audit_allowed`) are new objects per `Configuration`; never share or freeze them.
`tenant_fk` is bound when `belongs_to_tenant` runs; the role predicates and the identity associations' class names (`tenant_model`, `user_model`, `membership_model`) when the identity concerns are included; every other setting is read per call. Configure in an initializer.
Specs: `reset_configuration!` runs after each example (`spec/rails_helper.rb`); do not rely on a setting surviving an example.
Adding a setting: also `spec/contract_spec.rb` (default and writer count), `spec/configuration_spec.rb` (accepted and rejected values), the README settings table, `lib/generators/tenancy_dable/install/templates/initializer.rb.tt`, the settings counts and lists in `DESIGN.md`, `CHANGELOG.md`, `docs/domains/configuration.md`.
Changing a default is breaking for hosts that never set it: note it in `UPGRADING.md`.
Narrative: docs/domains/configuration.md
