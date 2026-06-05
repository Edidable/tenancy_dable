# frozen_string_literal: true

require "rails/railtie"

module TenancyDable
  # Rails integration point. Required (and therefore registered) when the gem is
  # loaded inside a Rails process — both a host app and the Combustion test
  # harness — BEFORE the application initializes (see spec/rails_helper.rb).
  #
  # The on_load hooks are registered at require time and fire when each framework
  # component loads, so they work regardless of whether the gem is required
  # before or after Rails. They delegate to `install_*` class methods whose
  # bodies are filled in by later phases:
  #
  #   * Phase 03 — prepend RelationExtension, make Scoped available on AR.
  #   * Phase 04 — mix the identity concerns into the host models.
  #   * Phase 05 — mix Controller::Resolvable into ActionController.
  #
  # Centralising the wiring here means downstream phases touch one method body,
  # never the boot sequence.
  class Railtie < ::Rails::Railtie
    ActiveSupport.on_load(:active_record) do
      TenancyDable::Railtie.install_active_record!
    end

    ActiveSupport.on_load(:action_controller) do
      TenancyDable::Railtie.install_action_controller!
    end

    # Wire the scoping engine into ActiveRecord (Phase 03) and make the identity
    # concerns (Phase 04) available. Loaded lazily here, on `:active_record`,
    # rather than from the entry file so the units that need AR only load once it
    # is present (DESIGN.md §2).
    def self.install_active_record!
      require "tenancy_dable/scoped"
      require "tenancy_dable/relation_extension"

      # Identity concerns (DESIGN.md §6). Required (not auto-included) so they are
      # defined before the host's models autoload and can `include` them — mirroring
      # how `Scoped` is offered to `Widget`. The install generator (Phase 07) tells
      # hosts to add the includes; the Combustion fixtures do so directly.
      require "tenancy_dable/models/tenant_model"
      require "tenancy_dable/models/membership_model"
      require "tenancy_dable/models/user_model"

      # Prepend so the bulk-write guard wraps AR's own update_all/delete_all/
      # destroy_all via `super`. `Scoped` becomes available for host models to
      # `include` simply by being required above.
      ActiveRecord::Relation.prepend(TenancyDable::RelationExtension)
    end

    # Wire the slug-resolution concern (Phase 05) into ActionController so host
    # controllers gain the `resolve_tenant!` macro and the `default_url_options`
    # slug injection. Required lazily here, on `:action_controller` load, for the
    # same reason the AR units are required in `install_active_record!` — pull in
    # the unit that needs ActionController only once it is present (DESIGN.md §2).
    #
    # `ActionController::Base` is the target: this is a full-stack SaaS skeleton
    # whose `default_url_options` slug injection is a view/routing concern. API
    # controllers can `prepend TenancyDable::Controller::Resolvable` directly.
    #
    # PREPEND, not include: `ActionController::Base` defines `default_url_options`
    # in its own class body, which out-ranks any *included* module — only a
    # prepended module lands ahead of it in the ancestry so our override runs and
    # `super` still reaches the framework default. `ActiveSupport::Concern`
    # extends `ClassMethods` for prepend too, so the `resolve_tenant!` macro is
    # unaffected. `prepend` is idempotent, so the `:action_controller` hook firing
    # more than once (Base + API) re-runs this harmlessly.
    def self.install_action_controller!
      require "tenancy_dable/controller/resolvable"

      ActionController::Base.prepend(TenancyDable::Controller::Resolvable)
    end
  end
end
