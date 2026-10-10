# frozen_string_literal: true

require "rails_helper"

# The gem's validation messages are error keys with shipped `en` and `pt-BR`
# defaults (DESIGN.md §16.6). A host override wins at every level of Active
# Model's lookup chain; `errors.details` carries the key, not the English text.
RSpec.describe "TenancyDable validation messages (i18n)" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  def cross_tenant_widget
    parent_in_b = create(:widget, tenant: tenant_b)
    build(:widget, tenant: tenant_a, parent: parent_in_b).tap(&:valid?)
  end

  def last_owner_membership
    owner = create(:membership, tenant: tenant_a, role: "owner")
    owner.role = "member"
    owner.save
    owner
  end

  def bad_slug_tenant
    Tenant.new(name: "Bad", slug: "Bad Slug").tap(&:valid?)
  end

  # Translations an example stores go away with the backend's store.
  def store_translations(locale, data)
    I18n.backend.store_translations(locale, data)
  end

  after { I18n.backend.reload! }

  describe "English defaults" do
    it "renders cross_tenant" do
      expect(cross_tenant_widget.errors[:parent]).to eq(["belongs to a different tenant"])
    end

    it "renders last_owner" do
      expect(last_owner_membership.errors[:role])
        .to eq(["cannot be changed: a tenant must keep at least one owner"])
    end

    it "renders slug_format" do
      expect(bad_slug_tenant.errors[:slug])
        .to include("must be lowercase letters, numbers, and single hyphens")
    end

    it "keeps CrossTenantError::MESSAGE equal to the :en default" do
      expect(TenancyDable::CrossTenantError::MESSAGE)
        .to eq(I18n.t("errors.messages.cross_tenant", locale: :en))
    end
  end

  describe "pt-BR defaults" do
    around { |example| I18n.with_locale(:"pt-BR", &example) }

    it "renders cross_tenant" do
      expect(cross_tenant_widget.errors[:parent]).to eq(["pertence a outro tenant"])
    end

    it "renders last_owner" do
      expect(last_owner_membership.errors[:role])
        .to eq(["não pode ser alterado: um tenant precisa manter ao menos um proprietário"])
    end

    it "renders slug_format" do
      expect(bad_slug_tenant.errors[:slug])
        .to include("deve ter apenas letras minúsculas, números e hífens simples")
    end
  end

  describe "host overrides" do
    it "wins at the model-attribute level" do
      store_translations(:en, activerecord: {errors: {models: {widget: {attributes: {parent: {cross_tenant: "wrong workspace"}}}}}})

      expect(cross_tenant_widget.errors[:parent]).to eq(["wrong workspace"])
    end

    it "wins at errors.messages" do
      store_translations(:en, errors: {messages: {last_owner: "keep an owner"}})

      expect(last_owner_membership.errors[:role]).to eq(["keep an owner"])
    end

    it "wins at errors.messages for the slug format" do
      store_translations(:en, errors: {messages: {slug_format: "bad slug"}})

      expect(bad_slug_tenant.errors[:slug]).to include("bad slug")
    end

    it "does not leak into later examples" do
      expect(cross_tenant_widget.errors[:parent]).to eq(["belongs to a different tenant"])
    end
  end

  describe "load order (B2)" do
    it "puts the gem's locale files before the host's, so a host file wins" do
      gem_en = File.expand_path("../../lib/tenancy_dable/locale/en.yml", __dir__)
      host_en = File.expand_path("../internal/config/locales/en.yml", __dir__)
      paths = I18n.load_path.map(&:to_s)

      expect(paths.index(gem_en)).to be < paths.index(host_en)
      expect(I18n.t("harness_only.host_locale_loaded", locale: :en)).to eq("host locale file")
    end
  end

  describe "errors.details" do
    it "carries :cross_tenant" do
      expect(cross_tenant_widget.errors.details[:parent]).to eq([{error: :cross_tenant}])
    end

    it "carries :last_owner" do
      expect(last_owner_membership.errors.details[:role]).to eq([{error: :last_owner}])
    end

    it "keeps :invalid for the slug format" do
      expect(bad_slug_tenant.errors.details[:slug]).to include(a_hash_including(error: :invalid))
    end
  end

  describe "prepend wiring (N6)" do
    around do |example|
      saved = I18n.load_path.dup
      example.run
    ensure
      I18n.load_path = saved
      I18n.backend.reload!
    end

    it "moves the gem's files ahead of a host file appended earlier, so the host still wins" do
      files = TenancyDable::Railtie.locale_files(ActiveSupport::OrderedOptions.new)
      host = File.expand_path("../internal/config/locales/en.yml", __dir__)
      I18n.load_path = [host, *files]

      TenancyDable::Railtie.prepend_load_path(files)

      expect(I18n.load_path.first(files.size)).to eq(files)
      expect(I18n.load_path.index(files.first)).to be < I18n.load_path.index(host)
      expect(I18n.load_path.count(files.first)).to eq(1)
    end
  end
end
