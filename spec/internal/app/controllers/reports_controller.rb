# frozen_string_literal: true

# Integration harness controller (Phase 13). Exercises slug resolution AND the
# Pundit policy scope TOGETHER in a single request: `resolve_tenant!` publishes
# `current_tenant` / `current_membership` from the `/:tenant_slug`, then `index`
# builds a `Policy::Context` from that resolved state and renders the ids the
# `TenancyDable::Policy::Base::Scope` exposes. The body is the observation channel
# (CurrentAttributes is reset once the response is sent), exactly as
# WidgetsController#index does for the resolution specs.
class ReportsController < ApplicationController
  resolve_tenant!

  def index
    context = TenancyDable.pundit_context(
      user: TenancyDable.current_membership&.user,
      tenant: TenancyDable.current_tenant,
      membership: TenancyDable.current_membership
    )

    # Resolve against `Widget.unscoped` so the POLICY scope's tenant filter is the
    # ONLY filter in play (the model's own default scope is bypassed). An empty or
    # filtered result is then provably the work of `Policy::Base::Scope#resolve`,
    # not masked by the model default scope — the same isolation technique
    # spec/policy/scope_spec uses with `without_tenant`.
    visible = TenancyDable::Policy::Base::Scope.new(context, Widget.unscoped).resolve

    render plain: visible.order(:id).pluck(:id).join(",")
  end
end
