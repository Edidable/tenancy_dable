# frozen_string_literal: true

Rails.application.routes.draw do
  # Tenant-scoped routes nest under the slug so TenancyDable::Controller::Resolvable
  # (`resolve_tenant!`) can resolve the workspace from the URL — slug only, never an
  # id (security invariant 5). `widgets_path` therefore takes a `:tenant_slug`, which
  # `default_url_options` fills from the active tenant so callers can omit it.
  # Exercised by the resolution request specs (Phase 10).
  scope ":tenant_slug" do
    resources :widgets, only: :index
    # Integration (Phase 13): a second resolved endpoint that ALSO applies the
    # Pundit policy scope, so spec/integration can prove resolution + authorization
    # compose end-to-end (see ReportsController).
    resources :reports, only: :index
  end
end
