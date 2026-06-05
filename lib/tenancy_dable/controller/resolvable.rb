# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  module Controller
    # Controller concern that resolves the active workspace from the URL slug,
    # enforces membership, and publishes the tenant + membership for the request.
    # The railtie PREPENDS it onto `ActionController::Base` on `:action_controller`
    # load (DESIGN.md §2/§9.1) — prepend, because `default_url_options` is defined
    # in Base's own class body and only a prepended override out-ranks it. A
    # controller then opts in with the `resolve_tenant!` macro. Hosts whose
    # controllers don't descend from `ActionController::Base` (e.g. an API base) can
    # `prepend TenancyDable::Controller::Resolvable` directly.
    #
    # SLUG ONLY (security invariant 5): resolution reads `params[slug_param]` and
    # looks the tenant up by its `slug`. It never reads or trusts a tenant *id*
    # from the URL, so a numeric id sitting in the slug position simply fails to
    # resolve — there is no id-based read path into a workspace.
    #
    # AUTH-AGNOSTIC: the acting user comes from `config.current_user_resolver`, run
    # with `instance_exec` so a host resolver executes in the controller's context
    # and can reach controller helpers (`-> { current_user }`). The gem ships a
    # default that reads the host's top-level `Current.user`; nothing here assumes
    # Devise/Warden/any particular auth stack.
    module Resolvable
      extend ActiveSupport::Concern

      class_methods do
        # Install the resolution `before_action`. Any options (`only:`, `except:`,
        # `if:`, `unless:`, `prepend:`, ...) pass straight through to
        # `before_action`, so a host can scope resolution to specific actions.
        def resolve_tenant!(**before_action_opts)
          before_action(:tenancy_dable_resolve_tenant, **before_action_opts)
        end
      end

      # Inject the active tenant's slug into generated URLs so path/url helpers
      # nested under the `/:tenant_slug` scope can omit it. Merges on top of
      # whatever the framework (or a host override higher in the ancestry) already
      # returns, and contributes nothing when no tenant is active — so it is inert
      # outside tenant-scoped requests.
      def default_url_options
        options = defined?(super) ? super : {}
        slug = TenancyDable.current_tenant&.slug
        return options if slug.nil?

        options.merge(TenancyDable.configuration.slug_param => slug)
      end

      private

      # The `before_action` body. Order (DESIGN.md §9.1), every step slug-driven:
      #   1. find the tenant by slug (honoring `on_tenant_not_found`),
      #   2. resolve the acting user (auth-agnostic, via `current_user_resolver`),
      #   3. require a membership or raise `NotAMemberError`,
      #   4. publish `current_tenant` + `current_membership`.
      def tenancy_dable_resolve_tenant
        config = TenancyDable.configuration
        tenant = tenancy_dable_find_tenant(config)

        # Reachable only when `on_tenant_not_found == :null` (the `:raise` path has
        # already raised `ActiveRecord::RecordNotFound`). A null tenant means "no
        # workspace in context": there is nothing to require membership in, so
        # publish a cleared context and stop.
        if tenant.nil?
          TenancyDable.current_tenant = nil
          TenancyDable.current_membership = nil
          return
        end

        user = instance_exec(&config.current_user_resolver)
        membership = user&.membership_for(tenant)
        if membership.nil?
          raise TenancyDable::NotAMemberError,
            "acting user is not a member of tenant #{tenant.slug.inspect}"
        end

        TenancyDable.current_tenant = tenant
        TenancyDable.current_membership = membership
      end

      # Look the tenant up BY SLUG (never by id — invariant 5). `:raise` (the
      # default) uses `find_by!`, so a miss raises `ActiveRecord::RecordNotFound`
      # (DESIGN.md §10-A); `:null` uses `find_by`, so a miss returns nil and
      # resolution proceeds workspace-less.
      def tenancy_dable_find_tenant(config)
        slug = params[config.slug_param]
        model = config.tenant_class
        if config.on_tenant_not_found == :null
          model.find_by(slug: slug)
        else
          model.find_by!(slug: slug)
        end
      end
    end
  end
end
