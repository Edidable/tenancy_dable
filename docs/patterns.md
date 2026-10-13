# Patterns

> The conventions every file in `lib/` follows. A change that breaks one of them needs a decision recorded in `docs/decisions.md`, not a one-off exception.

## Framework Classes Are Extended by Prepend, from the Railtie

The gem reaches into Rails only through [FILE:lib/tenancy_dable/railtie.rb]. It registers `ActiveSupport.on_load(:active_record)` and `on_load(:action_controller)` hooks at require time, and the hooks delegate to `install_active_record!` and `install_action_controller!`, so the wiring runs now or when the framework component loads, whichever comes later, provided the railtie is loaded before the application initializes, and every other file stays free of boot order. The extensions are [METHOD:prepend] on [CLASS:ActiveRecord::Relation], [CLASS:ActiveRecord::InsertAll] and [CLASS:ActionController::Base], never `include` or monkey-patching in place. A prepended override wraps the framework method through `super` and out-ranks a method defined in the class body, which is why `Resolvable#default_url_options` must be prepended: `ActionController::Base` has its own `default_url_options` (a `class_attribute` reader that `ActionDispatch::Routing::UrlFor` generates on the class), and an included module would never run. `prepend` is idempotent, so a hook that fires more than once (Base and API) is harmless. The boot order is in [FILE:docs/domains/boot.md].

## Hooks Forward With `(...)` and Keep Rails' Visibility

An override that does not read its arguments declares `(...)` and calls `super`, so a Rails line that adds or renames a parameter does not break the hook; one that must read them (`update_all(updates)`, `update_columns(attributes)`) names exactly the parameters Active Record defines on every supported line. The public hooks (`pluck`, `exists?`, `ids`, `load_async`, `compute_cache_version`, `arel`) stay public, and the private ones (`exec_queries`, `perform_calculation`) are defined under `private` in the module so the prepend keeps them private. [SPEC:spec/contract_spec.rb] asserts the visibility of each, so a Rails line that changes one fails the contract spec on purpose. A hook never reads state that its own guard would recurse into: the classifier reads `where_clause` and `unscope_values`, never `arel`.

## Walk Arel by Duck Typing

Code that inspects Arel nodes tests what a node responds to (`children`, `left` and `right`, `expr`, `attribute`) and never its Rails-version-specific class hierarchy, because the shape of `Or` differs between the oldest supported Rails line and the later ones. A literal pin is read as `value_before_type_cast`; a right side without one is not a pin.

## Guards Are Decision Trees That Mirror `DESIGN.md`

Every guard is a short, ordered decision tree whose steps are frozen in `DESIGN.md`: the default scope, the read guard, the bulk-write guard, the foreign-tenant refusal, the isolation check and the bypass. The code is written in the same order as the tree, with early returns for the pass-through cases (not scoped, bypass on, no current tenant) before the raise. A guard that has an escape names it in its message, for example "enter the tenant with TenancyDable.with_tenant". The messages of every guard carry the model name and tenant ids only, never a record or an attribute value; the one identifier beyond ids is the tenant slug that `NotAMemberError` names (see invariant 6 in `docs/architecture.md`).

## Every Gem Error Descends From `TenancyDable::Error`

All errors are defined in [FILE:lib/tenancy_dable/errors.rb] under [CLASS:TenancyDable::Error], so a host can `rescue TenancyDable::Error` for any tenancy failure with one clause, and [SPEC:spec/contract_spec.rb] locks the list. The file has no dependencies and is required first so every other file can reference it. A misconfiguration found at class load or at `configure` time raises [ERROR:TenancyDable::ConfigurationError], reused for a bad declaration, rather than a new class. An error that is a refusal of a tenant boundary is a sibling named for what it refuses (`BulkWriteError`, `CrossTenantReadError`, `CrossTenantWriteError`). Adding an error also touches the README errors table (see `docs/domains/errors.md`).

## Code Comments Cite the Frozen Contract

A comment that explains why code is shaped a certain way points at the section of [FILE:DESIGN.md] that freezes it, written as `DESIGN.md §N` or `(§16.1)`, rather than restating the contract. The contract is the single place a signature or a decision tree is defined; the comment is a pointer. Use the pointer sparingly: a comment states WHY a non-obvious line exists, and a pointer is for the frozen shape.

## Value Objects Are `Data.define`

Immutable values are [METHOD:Data.define] types: [CLASS:TenancyDable::Declaration], [CLASS:TenancyDable::Audit::Finding], [CLASS:TenancyDable::Snapshot] and [CLASS:TenancyDable::Policy::Context]. They are frozen, compare by value and have no Active Record dependency, which keeps `Policy::Context` and `Snapshot` usable in specs and policies without a database.

## Settings Are Validated in `validate!` and Read Lazily

Every setting lives on [CLASS:TenancyDable::Configuration] with its default in `initialize` and its rule in `validate!`, which `TenancyDable.configure` runs after the host's block and which raises [ERROR:TenancyDable::ConfigurationError] for an invalid value. Model names are strings that are constantized lazily (`tenant_class`, `user_class`, `membership_class`), so the host's models need not be loaded when the gem is configured. A value that can change between requests, such as [CONFIG:require_tenant], is read at query time, not captured; a value that defines structure is bound once: the tenant column when a model declares itself scoped, and the role predicates and identity associations' class names when the identity concerns are included. Adding a setting also touches the generator template and the README table (see `docs/domains/configuration.md`).

## All State Is Written Through the Facade

Tenant state is written only by the facade's writers, and `Current` holds raw state with no behaviour. The one private writer of the bypass flag, `scope_disabled_as`, sets it for a block and restores the prior value in `ensure`, so nesting is safe; `with_tenant` restores the prior tenant and membership the same way and routes both entry and restore through `current_tenant=`, so the RLS hook tracks the change in both directions. Any new code that changes the tenant goes through these writers.

## Gem-Defined Methods on Host Classes Are Prefixed

Methods and callbacks the gem adds to a host's classes carry a `tenancy_` or `tenancy_dable_` prefix (`tenancy_guard_read!`, `tenancy_pin_state`, `tenancy_declare!`, `tenancy_dable_resolve_tenant`), and helpers that are not part of the public surface are `private`. The public names a host uses are the contract: `belongs_to_tenant`, `tenant_global`, `resolve_tenant!`, `with_tenant` and the rest of the facade. A `private_constant` hides a constant that is an implementation detail.

## Optional Dependencies Are Opt-In Files

A file that needs an optional framework component is not required by the entry file. [FILE:lib/tenancy_dable/job.rb] and [FILE:lib/tenancy_dable/channel.rb] are required by the host (`require "tenancy_dable/job"`, `require "tenancy_dable/channel"`) and name no Active Job or Action Cable constant at load time beyond what the including class provides, so loading the gem never fails when the component is absent. Pundit is required lazily at the one place a Pundit constant is raised, the `on_not_a_member = :not_authorized` branch of `Resolvable`.

## Callbacks That Guard Are Prepended

The foreign-tenant refusal callbacks are registered with `prepend: true` so they run ahead of every validator and every host callback. The refusal depends on this: a uniqueness validator that reads would otherwise raise the read error before the write refusal. The same ordering is why a callback-free write (`touch`, `update_columns`, `delete`) has its own override that runs the same check.

## Style

Every Ruby file in `lib/` begins with `# frozen_string_literal: true`, except the generator's model template. The lint is Standard, run in CI (see `docs/domains/release.md`). Tests prove behaviour through the Combustion harness against real Active Record rather than mocks (see `docs/domains/testing.md`).
