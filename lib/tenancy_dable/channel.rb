# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # Action Cable concern — the Cable parallel to `Controller::Resolvable` (§9.1):
  # it resolves the active workspace from the subscription's slug param, enforces
  # membership, and runs every channel action inside the tenant context, so a
  # channel's reads scope and its bulk writes pass the guard exactly as a
  # controller action's do (DESIGN.md §14.1).
  #
  # OPT-IN, like `Job` (§10-I): this file is deliberately NOT required by the gem
  # entry point, so Action Cable stays an OPTIONAL dependency — a host that runs
  # channels does `require "tenancy_dable/channel"` and `include`s this into an
  # `ActionCable::Channel::Base` subclass (which provides `params`, `stream_from`,
  # `reject`, and `perform_action`). Nothing here names an Action Cable constant,
  # so merely loading the gem without Action Cable present never errors.
  #
  # THE GEM DOES NOT OWN CABLE AUTH (guardrail): connection-level user
  # identification stays the host's job. Its `ApplicationCable::Connection`
  # declares `identified_by :current_user` and establishes it however it
  # authenticates (cookie/session/token); Action Cable then exposes `current_user`
  # as a delegated reader on the channel. This concern only READS `current_user`
  # off the connection — it never establishes it, and ships no auth code.
  #
  # SLUG ONLY (security invariant 5): resolution reads `params[slug_param]` from
  # the subscription and looks the tenant up by its `slug`; it never reads or
  # trusts a tenant *id* from the params. Unlike the controller path it uses the
  # non-bang `find_by` (nil-on-miss), because a channel `reject`s rather than
  # raising `RecordNotFound`; the controller-only `on_tenant_not_found` setting is
  # not consulted here (so no new config setting).
  module Channel
    extend ActiveSupport::Concern

    # The tenant for THIS subscription, looked up BY SLUG (invariant 5 — never an
    # id) from the subscription params. Memoized for the subscription's lifetime;
    # nil when the slug param is absent or matches no tenant.
    def current_tenant
      config = TenancyDable.configuration
      @_tenancy_dable_tenant ||= config.tenant_class.find_by(slug: params[config.slug_param])
    end

    # The acting user's membership in `current_tenant`, or nil. `current_user`
    # comes from the connection's `identified_by :current_user` (host-owned auth);
    # a nil user — or a nil tenant — yields a nil membership. Memoized like the
    # tenant, for the subscription's lifetime.
    def current_membership
      @_tenancy_dable_membership ||= current_user&.membership_for(current_tenant)
    end

    # Whether the acting user is a member of `current_tenant`.
    def tenant_member?
      current_membership.present?
    end

    # The Cable parallel to Resolvable's membership enforcement — call in
    # `#subscribed`: rejects the subscription unless the acting user is a member of
    # `current_tenant`. A nil/unknown tenant yields a nil membership, so the
    # subscription is rejected (the secure outcome).
    def reject_unless_member!
      reject unless tenant_member?
    end

    # Subscribe to the tenant-namespaced stream `"tenant:<id>"` (plus `":<suffix>"`
    # when a suffix is given) — never a cross-tenant stream name. Call AFTER
    # membership is confirmed, so `current_tenant` is present.
    def stream_for_tenant(suffix = nil)
      name = "tenant:#{current_tenant.id}"
      name = "#{name}:#{suffix}" if suffix
      stream_from name
    end

    # Run a block inside the resolved tenant context — tenant AND membership both
    # set — for DB reads in `#subscribed`, where there is no auto-wrap. The tenant
    # and the prior membership are restored on exit by `with_tenant`'s ensure (§3),
    # so nothing leaks past the block.
    def with_tenant_context(&block)
      TenancyDable.with_tenant(current_tenant) do
        TenancyDable.current_membership = current_membership
        block.call
      end
    end

    # AUTO CONTEXT: Action Cable routes every client-invoked action method through
    # `#perform_action`, so wrapping it (calling `super` inside
    # `with_tenant_context`) makes each action handler tenant-scoped exactly like a
    # controller action — without every action method having to remember to wrap
    # itself. Bare `super` forwards `data` unchanged, so framework dispatch is
    # otherwise untouched.
    #
    # MUST stay PUBLIC: the base `ActionCable::Channel::Base#perform_action` is
    # public and the framework dispatches via an EXPLICIT receiver
    # (`ActionCable::Connection::Subscriptions` calls `find(data).perform_action`),
    # as does the channel TestCase's `perform`. A private override would raise
    # `NoMethodError` and break message dispatch entirely. It is NOT part of the
    # frozen public surface (the six helpers above) — `spec/contract_spec.rb` locks
    # those by responds-to, not by an exhaustive public-method match.
    def perform_action(data)
      with_tenant_context { super }
    end
  end
end
