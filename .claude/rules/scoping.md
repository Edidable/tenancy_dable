---
paths:
  - "lib/tenancy_dable/scoped.rb"
  - "lib/tenancy_dable/relation_extension.rb"
  - "lib/tenancy_dable/insert_all_extension.rb"
  - "spec/scoping/**"
  - "spec/integration/bulk_write_flow_spec.rb"
  - "spec/integration/cross_tenant_isolation_spec.rb"
  - "spec/security/**"
---
Never call `where_values_hash` or `where_clause.to_h` from a guard: Active Record raises on a function-left equality (`lower(name) = ?`). Read literal pins from `where_clause.ast`. Proof: `spec/scoping/read_guard_spec.rb` ("the classifier reads literal pins").
The read guard and the bulk-write guard share one classifier, `tenancy_pin_state`; change its states or their ORDER (other, current, marker, unscope, any fk predicate, unpinned) and both specs change: `read_guard_spec.rb` and `bulk_write_guard_spec.rb`.
The bulk-write guard accepts only `:current`; the read guard refuses `:other` and `:removed` only. `guard_reads = false` never touches the bulk-write guard.
An explicit nil pin (`IS NULL` Equality) stays `:unpinned` when nothing else pins the column (beside the default scope's pin it is `:current`); any other predicate on the fk is `:removed`. Never widen that exemption.
The default scope's two unfiltered branches (bypass, fail-open) must return `extending(BuiltWithoutTenant)`; `Model.unscoped` stays unmarked and passing. Proof: `spec/contract_spec.rb`, `read_guard_spec.rb`.
Reads hook `exec_queries` and `perform_calculation` (private) plus `pluck`, `exists?`, `ids`, `load_async`, `compute_cache_version`, `arel` (public); a new read entry point gets an example in `read_guard_spec.rb` and a line in `spec/contract_spec.rb`. Hooking `arel` makes `to_sql` of a refused relation raise; the classifier must never call `arel`.
Hooks forward `(...)`; `update_all` takes `(updates)` because the guard reads it. Do not hand-write a parameter list on a hook that does not need one.
The foreign-tenant refusal is one helper, `tenancy_refuse_foreign_tenant!(fk, action)`: prepended `before_validation`, `before_save`, `before_destroy`, plus the `touch`, `update_columns` and `delete` overrides. It raises `CrossTenantWriteError`, never a validation error. Proof: `foreign_record_write_spec.rb`, `create_refusal_spec.rb`.
A persisted record is judged by the tenant its ROW holds (`attribute_in_database`, or an `unscoped` lookup for a partial select), never by an unsaved assignment.
`update_columns`/`update_column` raise `TenantImmutableError` on a different tenant value even with no tenant and inside `without_tenant`; the Hash `update_all` refusal lifts inside `without_tenant`. Both resolve attribute aliases and compare case-insensitively.
`InsertAllExtension` hooks `initialize(...)` and reads the resolved state after `super` (the argument list differs between Active Record lines). Rules: every row's effective fk is the current tenant; an upsert's conflict columns include the fk (a composite primary key with the fk passes). Empty inserts are not inspected. Proof: `insert_all_guard_spec.rb`.
Messages carry the model name and tenant ids only, never a record payload or a slug.
`belongs_to_tenant` binds `tenant_fk` at declaration (the default scope, the auto-assign, the writer, the validation, the uniqueness helper and the refusal callbacks); the guards and the `touch`/`update_columns`/`delete` overrides read it per call. Set the setting before models load.
The cross-tenant `belongs_to` validation reads the target `unscoped` on purpose and ADDS an error; do not turn it into a raise.
A fail-closed host raises `NoTenantError` even on `Model.new`; build fixtures before arming `require_tenant`.
Residuals (`unscoped` with no pin, `except(:where)`, `only`, `or` with an unscoped or stale relation, SQL strings, `reload` by id) are documented limits: record a new one in the read-guard spoke and the README, do not paper over it with a looser classifier.
`increment!`, `update_counters` and `counter_cache` on a scoped model raise `BulkWriteError` (inside a tenant and with none); do not weaken the bulk guard to fix it.
Narrative: docs/domains/scoping.md
