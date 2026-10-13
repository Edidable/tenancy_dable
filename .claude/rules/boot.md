---
paths:
  - "lib/tenancy_dable/railtie.rb"
  - "lib/tenancy_dable.rb"
---
The railtie holds no logic: the hooks delegate to `install_active_record!` and `install_action_controller!`. Put new attachments in those bodies.
Order inside `install_active_record!` is load-bearing: extend `ActiveRecord::Base` with `Declarations` FIRST, then require `scoped` and `relation_extension`, then the identity concerns, then the `Relation` prepend, then require and prepend `InsertAllExtension`. The identity concerns call `tenant_global` and `Scoped` calls `tenancy_declare!` when a model includes them; the macro must already exist. Proof: `spec/declarations/declarations_spec.rb`, plus the eager load in `spec/rails_helper.rb`.
`Scoped` and the identity concerns are required, never auto-included; which models are tenant-aware stays the host's explicit choice.
`Resolvable` is PREPENDED onto `ActionController::Base`, never included: Base has its own `default_url_options` (a `class_attribute` reader that `ActionDispatch::Routing::UrlFor` generates on the class), which outranks an included module. Proof: `spec/resolution/default_url_options_spec.rb`.
`ActionController::Base` is the only target; an API base prepends `Resolvable` itself. Prepend is idempotent, so the hook firing twice is harmless.
Relation and InsertAll are prepended so the guards wrap Active Record's own methods through `super`. Proof: `spec/contract_spec.rb` proves the insert-all prepend through the ancestry and locks the Relation extension's method list and visibility; the Relation prepend itself is proven by the guard specs under `spec/scoping/`.
The entry file requires only Active Record-free units (errors, configuration, current, snapshot, audit, policy context and base) plus the railtie. Do not require `scoped`, `declarations`, models, `job` or `channel` from `lib/tenancy_dable.rb`.
`tenancy_dable/job` and `tenancy_dable/channel` stay opt-in so ActiveJob and Action Cable stay optional; generators are never required at boot.
i18n: compute locale files in the `tenancy_dable.i18n` initializer (it needs the host's `config.i18n`), register the prepend on `on_load(:i18n)`, and prepend so host files win. Proof: `spec/i18n/locale_files_spec.rb`, `spec/i18n/messages_spec.rb`.
The rake task file is loaded from the `rake_tasks` block. Proof: `spec/declarations/audit_task_spec.rb`.
If you add an attachment, also add a contract assertion in `spec/contract_spec.rb` and update the order list in the narrative.
Narrative: docs/domains/boot.md
