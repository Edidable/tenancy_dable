# frozen_string_literal: true

require "rails_helper"

# `default_url_options` (DESIGN.md §9.1; PLAN.md). Once a workspace is active the
# resolver injects its slug into URL generation, so nested path/url helpers can
# OMIT the `:tenant_slug` segment — `widgets_path` "just works" without callers
# threading the slug through every link. When no tenant is active the override
# contributes nothing, staying inert outside tenant-scoped requests. It is a
# read-only formatting concern, so these exercise it directly on a controller
# instance rather than through a full request.
RSpec.describe "TenancyDable::Controller::Resolvable#default_url_options" do
  let(:controller) { WidgetsController.new }

  describe "the merged option hash" do
    it "injects the active tenant's slug under the configured slug_param" do
      tenant = create(:tenant, slug: "acme")

      TenancyDable.with_tenant(tenant) do
        expect(controller.default_url_options).to eq(tenant_slug: "acme")
      end
    end

    it "contributes no slug_param key when no tenant is active" do
      expect(TenancyDable.current_tenant).to be_nil

      expect(controller.default_url_options).not_to have_key(:tenant_slug)
    end

    it "honors a custom slug_param name" do
      TenancyDable.configure { |c| c.slug_param = :workspace }
      tenant = create(:tenant, slug: "acme")

      TenancyDable.with_tenant(tenant) do
        expect(controller.default_url_options).to eq(workspace: "acme")
      end
    end
  end

  describe "path-helper integration" do
    it "lets a nested path helper omit the slug entirely" do
      tenant = create(:tenant, slug: "acme")
      controller.request = ActionDispatch::TestRequest.create

      TenancyDable.with_tenant(tenant) do
        # No tenant_slug argument — default_url_options supplies it from context.
        expect(controller.widgets_path).to eq("/acme/widgets")
      end
    end

    it "the slug segment is genuinely required, so the omission does real work" do
      # Generating the same path WITHOUT default_url_options' help fails: the
      # segment is mandatory, so the example above is not merely hitting an
      # optional param.
      expect {
        Rails.application.routes.url_helpers.widgets_path
      }.to raise_error(ActionController::UrlGenerationError, /tenant_slug/)
    end
  end
end
