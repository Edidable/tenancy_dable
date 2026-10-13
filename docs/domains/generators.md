# Generators

The gem ships two Rails generators, [FILE:lib/generators/tenancy_dable/install/install_generator.rb] and [FILE:lib/generators/tenancy_dable/model/model_generator.rb], with their templates beside them. Rails discovers them on demand from [FILE:lib/generators]; the railtie never requires them at boot. The specs are under [FILE:spec/generators/].

## Overview

[CMD:rails generate tenancy_dable:install] wires a host application. [CMD:rails generate tenancy_dable:model NAME field:type] scaffolds one tenant-scoped model and its migration. Neither generator edits an existing model: the install generator prints what the host must add, and the model generator writes new files.

## The install generator

[CLASS:TenancyDable::Generators::InstallGenerator] runs these steps in order:

1. It writes [FILE:config/initializers/tenancy_dable.rb], the commented configuration DSL with each setting shown at its default. [SPEC:spec/generators/install_generator_spec.rb] proves the file calls [METHOD:TenancyDable.configure] and is valid Ruby.
2. It writes a [FILE:create_tenants] migration (a [COLUMN:slug] that is NOT NULL and uniquely indexed, plus a [COLUMN:name]) and then a [FILE:create_memberships] migration ([COLUMN:user] and [COLUMN:tenant] references, a NOT NULL [COLUMN:role], and a unique index over [COLUMN:user_id] and [COLUMN:tenant_id]). The tenants migration is generated first so its timestamp orders ahead of the memberships foreign key. The spec proves the columns and indexes of both.
3. It writes [FILE:app/policies/application_policy.rb], an [CLASS:ApplicationPolicy] that subclasses [CLASS:TenancyDable::Policy::Base], aliases [CONST:Context] to [CLASS:TenancyDable::Policy::Context], and subclasses the base scope; its header comment shows the Pundit user hook (see `docs/domains/authorization.md`). The spec proves the superclass and the alias.
4. It writes [FILE:app/models/current.rb], a [CLASS:ActiveSupport::CurrentAttributes] class with a [FIELD:user] attribute, which the default [CONFIG:current_user_resolver] reads.
5. It injects a commented route scaffold into [FILE:config/routes.rb] right after the `routes.draw do` line: a `scope "/:<slug_param>"` block, inert until the host uncomments it. The scaffold reads [CONFIG:slug_param] live, so a host that reconfigured it first gets a matching scaffold. The spec proves the scaffold appears with the marker and the default scope line.
6. It prints the finishing instructions: for each of [CLASS:Tenant], [CLASS:User] and [CLASS:Membership] it says whether the model file exists and tells the host to add the matching identity concern, and it warns that the membership model must never include [MODULE:TenancyDable::Scoped].

[RULE:The install generator is idempotent]. Every step skips when its target exists, and says so: an existing initializer or policy is never overwritten, a migration with the same base name under any timestamp is never duplicated, an existing [FILE:app/models/current.rb] is left alone with a note to ensure it defines [FIELD:user], a missing [FILE:config/routes.rb] is skipped with a note, and the route scaffold is injected at most once, guarded by the marker constant [CONST:ROUTE_MARKER]. [SPEC:spec/generators/install_generator_spec.rb] proves a second run raises nothing, adds no migration, creates or clobbers no file, and leaves exactly one marker.

[RULE:The install generator touches nothing else]. It does not edit [FILE:app/models/tenant.rb], [FILE:app/models/user.rb] or [FILE:app/models/membership.rb], does not create those models, does not create the host's Pundit wiring in [FILE:app/controllers], and does not run migrations; the printed instructions tell the host to do each.

### Gotcha: The generated migrations use fixed table names

[SYMPTOM:a host whose tenant model is not Tenant ends up with a migration for the wrong table]. [CAUSE:the templates write the tables tenants and memberships and a user reference, independent of tenant_model, user_model and membership_model]. [FIX:rename the generated migration contents, or skip the generator's migrations, when the model names differ from the defaults]. [RULE:the initializer and the model names are the host's to keep consistent].

## The model generator

[CLASS:TenancyDable::Generators::ModelGenerator] takes a name and Rails-style attributes. It writes [FILE:app/models/<name>.rb] and a [FILE:create_<table>] migration.

- The model subclasses [CLASS:ApplicationRecord] (there is no parent option), includes [MODULE:TenancyDable::Scoped] and calls [METHOD:belongs_to_tenant]. Any other reference attribute becomes a [METHOD:belongs_to], polymorphic when requested. The spec proves the include, the declaration, the superclass and that the file is valid Ruby.
- The migration puts the tenant reference first, with the foreign key and a NOT NULL constraint, so the row always carries its owner and the reference supplies the index. The remaining columns come from the arguments; a tenant attribute passed explicitly is dropped so it is not written twice; indexed attributes get an [METHOD:add_index]; timestamps are on unless disabled with the [OPTION:timestamps] option.
- The reference name is derived from [CONFIG:tenant_fk] by dropping the `_id` suffix, so a host that configured [VALUE:workspace_id] gets a [METHOD:t.references :workspace]. [SPEC:spec/generators/model_generator_spec.rb] proves this and the default shape, and checks the migration text only.

The generator skips the class-collision check on purpose: that check inspects the loaded constant and not the destination, so it would wrongly abort when a model of that name is already loaded in the generating process.

### Gotcha: A non-default `tenant_fk` is honoured by the migration only

[SYMPTOM:with a custom [CONFIG:tenant_fk], the generated model's default scope and guards use the configured column, but its tenant association is keyed on `tenant_id`, and the migration references a table the install generator never creates]. [CAUSE:the model template emits a bare [METHOD:belongs_to_tenant], which builds `belongs_to :tenant` (foreign key `tenant_id`) while the scope reads the configured column, and the migration's `t.references :workspace, foreign_key: true` points at a `workspaces` table]. [FIX:edit the model to `belongs_to_tenant :workspace` (or pass `foreign_key:` and `class_name:`) and the migration to `foreign_key: { to_table: :tenants }`]. [RULE:review the generated model and migration against the configured column before running the migration].

## How the specs drive them

[SPEC:spec/generators/generator_helper.rb] runs a generator instance against a throwaway directory and pins its migration path to the relative [FILE:db/migrate]. The generator specs stay on the plain spec helper and not on the Rails harness: booting the harness makes Active Record resolve the migrate path to the harness's own absolute directory, and a migration would be written into the fixture application.

If you change what a generator emits, also update the generator spec, the printed instructions, `README.md`'s install section and, for a new setting, the initializer template (see `docs/domains/configuration.md`).

### Gotcha: Moving a generator spec onto the Rails harness

[SYMPTOM:running the suite adds migration files to the fixture application]. [CAUSE:with a booted application the migrate path is absolute and points at the harness]. [FIX:keep generator specs on the plain spec helper and drive the generator with the helper's run method]. [RULE:every generator step writes only under the destination root].
