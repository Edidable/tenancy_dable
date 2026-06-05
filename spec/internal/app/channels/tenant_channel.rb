# frozen_string_literal: true

# HARNESS fixture exercising TenancyDable::Channel end-to-end — the Cable
# parallel to WidgetsController in the resolution specs. It resolves the tenant
# from the subscription's slug param, enforces membership in `#subscribed`,
# streams the tenant-namespaced stream, and exposes one action whose tenant-scoped
# read proves the automatic `perform_action` context wrap.
class TenantChannel < ApplicationCable::Channel
  include TenancyDable::Channel

  # Cable parallel to a controller before_action: reject a non-member — or an
  # unknown/absent slug, which resolves to a nil tenant and therefore no
  # membership — otherwise stream the tenant-namespaced stream. `stream_for_tenant`
  # reads `current_tenant.id`, so it is guarded on a confirmed membership to stay
  # nil-safe on the reject path.
  def subscribed
    reject_unless_member!
    stream_for_tenant if tenant_member?
  end

  # A client-invoked action. Action Cable dispatches it through `perform_action`,
  # which the concern wraps in `with_tenant_context` — so this read scopes to the
  # subscription's tenant exactly like a controller action, with no per-action
  # wrapping. Transmit what was visible so a spec can observe BOTH the scoped
  # result AND that `TenancyDable.current_tenant` is set inside the action.
  def widget_count
    # Explicit braces: `transmit(data, via: nil)` has a keyword param, so a
    # braceless trailing hash would be parsed as keywords (Ruby 3 kwarg
    # separation) and leave the positional `data` empty.
    transmit({
      "widget_count" => Widget.count,
      "tenant_id" => TenancyDable.current_tenant&.id
    })
  end
end
