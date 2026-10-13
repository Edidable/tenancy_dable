# Boot

Boot is the order in which the gem's code loads and attaches to Rails. The code is [FILE:lib/tenancy_dable/railtie.rb] and the require list of [FILE:lib/tenancy_dable.rb]. Nothing in a host calls an installer: requiring the gem registers a railtie, and the railtie's hooks attach each unit when its framework component loads.

## Overview

The load happens in three stages: what the entry file requires, what the railtie attaches on each framework load hook, and what stays opt-in.

### At require time

[FILE:lib/tenancy_dable.rb] requires, in order: Active Support notifications, the version, the errors, the configuration, the current attributes, the snapshot, the audit, the policy context, the base policy and the railtie. Every unit in that list is free of Active Record and Action Controller at load time: the policy context is a pure [CLASS:Data] type, the current attributes load Active Support's own code generator, and the audit names Active Record only inside the method that runs it. The entry file then defines the facade module (configuration, current context, [METHOD:with_tenant], [METHOD:without_tenant], [METHOD:snapshot], [METHOD:carry], [METHOD:audit], [METHOD:pundit_context]) whose bodies reach Active Record lazily.

The railtie file registers four things when it is required, and does no wiring itself: an [METHOD:ActiveSupport.on_load(:active_record)] callback, an [METHOD:ActiveSupport.on_load(:action_controller)] callback, an initializer named [VALUE:tenancy_dable.i18n], and a [METHOD:rake_tasks] block. Because the callbacks wait for the framework component, the order of the gem's require against Rails's own loading does not matter; the gem only has to be required before the application initializes (the harness does so in [FILE:spec/rails_helper.rb]).

### On [VALUE:active_record] load

[METHOD:Railtie.install_active_record!] runs once Active Record is loaded and does these steps in this order:

1. It requires [FILE:tenancy_dable/declarations] and extends [CLASS:ActiveRecord::Base] with [MODULE:TenancyDable::Declarations], which supplies the class macro [METHOD:tenant_global] and the declaration readers to every model.
2. It requires [FILE:tenancy_dable/scoped] and [FILE:tenancy_dable/relation_extension]. [MODULE:TenancyDable::Scoped] is only required, never included: it becomes available for host models to include.
3. It requires the three identity concerns, [FILE:tenancy_dable/models/tenant_model], [FILE:tenancy_dable/models/membership_model] and [FILE:tenancy_dable/models/user_model], again only requiring them, so a host model can include one when it autoloads.
4. It prepends [MODULE:TenancyDable::RelationExtension] onto [CLASS:ActiveRecord::Relation], so the bulk-write guard and the read guard wrap Active Record's own methods through [METHOD:super].
5. It requires [FILE:tenancy_dable/insert_all_extension] and prepends [MODULE:TenancyDable::InsertAllExtension] onto [CLASS:ActiveRecord::InsertAll], because [METHOD:insert_all] and [METHOD:upsert_all] skip every callback and the create refusal cannot see them.

[RULE:Declarations is extended before the identity concerns are required and before any model includes one]. Each identity concern calls [METHOD:tenant_global] from its [METHOD:included] block, and a model that includes [MODULE:TenancyDable::Scoped] declares through [METHOD:belongs_to_tenant]; both need the declaration readers on [CLASS:ActiveRecord::Base] at include time, which is when the host's model autoloads. Extending first guarantees the macro exists by then. The host's models load after the hook fires, so the order inside the hook, not the host's code, is what is load-bearing. [SPEC:spec/declarations/declarations_spec.rb] proves the macro, the readers and the three identity models declaring themselves on include, and the harness eager-loads its models at boot (see `docs/domains/testing.md`), so a wrong order fails every spec.

[SPEC:spec/contract_spec.rb] proves the insert-all prepend through the ancestry and locks the Relation extension's method list and visibility; the Relation prepend itself is proven by the guard specs under `spec/scoping/`.

### On [VALUE:action_controller] load

[METHOD:Railtie.install_action_controller!] requires [FILE:tenancy_dable/controller/resolvable] and prepends [MODULE:TenancyDable::Controller::Resolvable] onto [CLASS:ActionController::Base]. The target is the full-stack base on purpose: the slug injection into generated URLs is a view and routing concern. A host whose controllers descend from another base, such as an API base, prepends the module onto it directly. The hook may fire for more than one component; prepend is idempotent, so the repeat is harmless.

[RULE:The controller concern is prepended, not included]. [CLASS:ActionController::Base] has its own [METHOD:default_url_options], a `class_attribute` reader that `ActionDispatch::Routing::UrlFor` generates on the class, and a method defined on the class outranks any included module. Only a prepended module lands ahead of the class in the ancestry, so the override runs and its [METHOD:super] still reaches the framework default. The concern's class method [METHOD:resolve_tenant!] is unaffected because [CLASS:ActiveSupport::Concern] extends the class methods for a prepend as well. [SPEC:spec/resolution/default_url_options_spec.rb] proves the override reaches a real controller and merges over the framework default; [SPEC:spec/resolution/successful_resolution_spec.rb] proves the macro installs the before_action.

### On [VALUE:i18n] load

The initializer [VALUE:tenancy_dable.i18n] computes the gem's locale files from the host's [METHOD:config.i18n] with [METHOD:Railtie.locale_files], and registers a hook on [VALUE:i18n] load that calls [METHOD:Railtie.prepend_load_path]. The files are the English file always, and the Brazilian Portuguese file only when the host declares [VALUE:pt-BR] in its default locale or available locales, given as symbols or strings. Prepending puts the gem's files first in [CONST:I18n.load_path], where a later file wins, so a host file for the same key wins however the host registered it: files from [FILE:config/locales] and from [METHOD:config.i18n.load_path] are added after the gem's initializer, and a path appended directly in the application class body is moved behind the gem's files by the prepend. Computing the files inside an initializer is what lets the gem see the host's [METHOD:config.i18n] and keep Brazilian Portuguese out of an English-only host's available locales. See `docs/domains/i18n.md`. [SPEC:spec/i18n/locale_files_spec.rb] proves which files each configuration gets, [SPEC:spec/i18n/messages_spec.rb] proves that the prepend moves the gem's files ahead of an earlier host file without duplicating them, and [SPEC:spec/contract_spec.rb] locks the file-selection contract.

### Rake tasks

The railtie's [METHOD:rake_tasks] block loads [FILE:lib/tenancy_dable/tasks/audit.rake], which defines [CMD:tenancy_dable:audit]: it depends on the environment, prints the findings and aborts with a non-zero status when there are any, and otherwise prints a single confirmation line. [SPEC:spec/declarations/audit_task_spec.rb] proves the exit behaviour; [SPEC:spec/contract_spec.rb] proves the file's path.

## What stays opt-in

Two concerns are never required by the entry file or the railtie, so their frameworks stay optional dependencies:

- [MODULE:TenancyDable::Job] is required with [FILE:tenancy_dable/job] by a host that runs jobs (see `docs/domains/jobs.md`).
- [MODULE:TenancyDable::Channel] is required with [FILE:tenancy_dable/channel] by a host that runs Action Cable (see `docs/domains/resolution.md`). It must be required before a channel class that includes it is defined, which for an eager-loading host means before the application initializes.

The generators under [FILE:lib/generators] are also never required at boot; Rails discovers them on demand (see `docs/domains/generators.md`). The identity concerns are required but never included automatically, and [MODULE:TenancyDable::Scoped] is required but never included: which models are tenant-aware is always an explicit host choice.

## Boundaries


[ABSENCE:The railtie holds no wiring logic of its own]. The hooks delegate to two class methods, [METHOD:install_active_record!] and [METHOD:install_action_controller!]; a change to what attaches where is a change to those two bodies and to this document's order lists.

If you add a unit that must attach to a framework class, put its require and its prepend or extend in the matching install method, in an order that respects the declarations-first rule above, and add a contract assertion in [FILE:spec/contract_spec.rb].
