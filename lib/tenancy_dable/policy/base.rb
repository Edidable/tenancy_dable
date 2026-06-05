# frozen_string_literal: true

module TenancyDable
  module Policy
    # Secure-by-default Pundit base policy. Every action returns `false` until a
    # subclass grants it, so forgetting to define an action DENIES rather than
    # leaks (DESIGN.md §9.3). The install generator's `ApplicationPolicy`
    # subclasses this (Phase 07); concrete policies subclass that.
    #
    # Policies decide on a `Policy::Context` (user + tenant + membership), never a
    # bare user — build one with `TenancyDable.pundit_context(...)`. The capability
    # helpers (`owner?`, `manager?`, `member?`, `same_tenant?`) and the context
    # readers are PRIVATE so Pundit's action introspection and `pundit-matchers`
    # don't mistake them for policy actions (DESIGN.md §10-D).
    class Base
      def initialize(context, record)
        @context = context
        @record = record
      end

      # --- secure-by-default actions ---------------------------------------
      # All deny unless a subclass overrides. `new?`/`edit?` delegate to
      # `create?`/`update?` (Rails-conventional; DESIGN.md §10-B) so granting the
      # write also grants its form.

      def index?
        false
      end

      def show?
        false
      end

      def create?
        false
      end

      def new?
        create?
      end

      def update?
        false
      end

      def edit?
        update?
      end

      def destroy?
        false
      end

      private

      attr_reader :context, :record

      # Context readers (private — see class note). Sourced from the Context so
      # there is one source of truth; `role` delegates to `Context#role`.
      def user
        context.user
      end

      def tenant
        context.tenant
      end

      def membership
        context.membership
      end

      def role
        context.role
      end

      # Does `record` belong to the active tenant? The `respond_to?` guard keeps
      # the helper safe on records that carry no `tenant_id` (non-scoped models),
      # so any policy can call it unconditionally (DESIGN.md §10-C).
      def same_tenant?
        record.respond_to?(:tenant_id) && record.tenant_id == tenant&.id
      end

      # Capability predicates, derived from config so they track the host's
      # configured role names rather than hard-coding them (DESIGN.md §9.3).
      def owner?
        role == TenancyDable.configuration.roles.first
      end

      def manager?
        TenancyDable.configuration.manager_role?(role)
      end

      def member?
        role.present?
      end

      # Pundit scope: the subset of `scope` the context may see. FAIL CLOSED
      # (security invariant 4) — with no active tenant resolve to NOTHING, never
      # every tenant's rows; with a tenant, filter by the configured fk. Concrete
      # policies inherit this via constant lookup (`WidgetPolicy::Scope`).
      class Scope
        def initialize(context, scope)
          @context = context
          @scope = scope
        end

        def resolve
          return scope.none if tenant.nil?

          scope.where(TenancyDable.configuration.tenant_fk => tenant.id)
        end

        private

        attr_reader :context, :scope

        def tenant
          context.tenant
        end
      end
    end
  end
end
