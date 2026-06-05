# frozen_string_literal: true

# Harness controller that exercises slug resolution end-to-end for the resolution
# specs (Phase 10). `resolve_tenant!` installs the before_action that resolves the
# tenant from `/:tenant_slug`, enforces membership, and publishes
# `TenancyDable.current_tenant` / `current_membership`.
#
# `index` echoes the resolved slug + role so a request spec can assert what the
# before_action established DURING the request — ActiveSupport::CurrentAttributes
# is reset by the executor once the response is sent, so the body is the reliable
# observation channel. With `on_tenant_not_found = :null` and an unknown slug both
# render blank (nil tenant/membership); the `:raise` and non-member paths never
# reach the action (the before_action raises first).
class WidgetsController < ApplicationController
  resolve_tenant!

  def index
    render plain: "tenant:#{TenancyDable.current_tenant&.slug} role:#{TenancyDable.current_membership&.role}"
  end
end
