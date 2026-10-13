---
paths:
  - "lib/generators/**"
  - "spec/generators/**"
---
Generators live under `lib/generators` and are discovered by Rails on demand; never require them from `lib/tenancy_dable.rb` or the railtie.
The install generator is idempotent: every step skips an existing target (initializer, policy, `Current`, routes marker, a migration of the same base name under any timestamp). Keep any new step skip-if-exists. Proof: `spec/generators/install_generator_spec.rb`.
Generate `create_tenants` before `create_memberships`, so the memberships foreign key's timestamp orders after its table.
The route scaffold is commented, injected once behind `ROUTE_MARKER`, and reads `slug_param` live.
The install generator never edits `app/models/{tenant,user,membership}.rb`; it only prints the include to add, and the warning that Membership never includes `Scoped`.
`ApplicationPolicy` template: subclass `Policy::Base`, keep the `Context` alias and the `Scope` subclass. If `Policy::Base` changes shape, change the template.
The `current.rb` template carries `attribute :user`, which the default `current_user_resolver` reads; keep them in step.
Model generator: `include TenancyDable::Scoped` plus `belongs_to_tenant`; the migration puts the tenant reference first with `null: false, foreign_key: true`, named from `tenant_fk` minus `_id`. Do not hard-code `:tenant`. A custom `tenant_fk` reaches the migration only: the model template emits a bare `belongs_to_tenant`. Proof: `spec/generators/model_generator_spec.rb`.
Do not add `check_class_collision` to the model generator (it inspects the loaded constant, not the destination).
Generator specs stay on `spec_helper`, never `rails_helper`, and run through `run_generator` (`spec/generators/generator_helper.rb`) into a tmp dir; the booted harness would make migrations land in `spec/internal/db/migrate`.
If you add a configuration setting, also add it to `lib/generators/tenancy_dable/install/templates/initializer.rb.tt`, and to the contract spec and README table.
Narrative: docs/domains/generators.md
