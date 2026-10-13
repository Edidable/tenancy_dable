---
paths:
  - "lib/tenancy_dable/declarations.rb"
  - "lib/tenancy_dable/audit.rb"
  - "lib/tenancy_dable/tasks/**"
  - "spec/declarations/**"
---
A declaration is a frozen `Declaration` (`kind`, `reason`, `tag`, `allow_tenant_fk`); `tenant_global` and `belongs_to_tenant` both end in the private `tenancy_declare!`, the only writer.
`tenancy_declare!` checks in a fixed order and stores nothing until all pass: reason, tag, `allow_tenant_fk`, existing declaration. Keep the order (`spec/declarations/declarations_spec.rb` "checks the reason before the tag").
`belongs_to_tenant` calls `tenancy_declare!` before `belongs_to` and the other installs, so a refused declaration leaves nothing behind; never forward `tag:` to `belongs_to`.
A bad or repeated declaration raises `ConfigurationError` with the model name (or "an anonymous model"). A subclass inherits via `tenancy_declaration`, so it can never redeclare, weaker included. A base class never declares tenancy: `tenant_global` on an abstract base is inherited, so no model below it is `:undeclared` and the audit goes silent.
`Declarations` is extended onto `ActiveRecord::Base` by the railtie BEFORE the identity concerns load; they call `tenant_global` at include time.
The audit reads class metadata and the schema only: no rows, and it never raises for a finding. Findings are `Data` values; the result is frozen and sorted by model name, then `Audit::KINDS` order.
Adding a finding kind: extend `KINDS`, `findings_for`, `spec/declarations/audit_spec.rb`, the README audit section, and the rake task spec if the output shape changes.
A global model on the same table as a scoped model is always flagged; `allow_tenant_fk` never excuses it (`audit_spec` ":global_with_tenant_fk").
Skips: abstract, real STI (same table as base), `audit_ignored_namespaces` by exact name or `::` prefix, `audit_allowed` keys; anonymous and stale classes in the no-argument form only. Explicit models get no eager load and no name filter.
The rake task aborts with one finding per line (exit 1) or prints one line (exit 0); `spec/declarations/audit_task_spec.rb` locks both. The railtie loads it via `rake_tasks`.
The index check counts a single-column index, a composite index, or a composite primary key that LEADS with `config.tenant_fk`.
Narrative: docs/domains/declarations.md
