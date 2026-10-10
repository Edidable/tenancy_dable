# frozen_string_literal: true

require "spec_helper"
require "active_support/ordered_options"

# Which of the gem's locale files a host gets (DESIGN.md §16.6).
RSpec.describe TenancyDable::Railtie, ".locale_files" do
  def names(**settings)
    config = ActiveSupport::OrderedOptions.new.merge!(settings)
    described_class.locale_files(config).map { |f| File.basename(f) }
  end

  it "loads en only for an English-only host" do
    expect(names).to eq(%w[en.yml])
    expect(names(default_locale: :en, available_locales: %i[en fr])).to eq(%w[en.yml])
  end

  it "adds pt-BR when it is the default locale" do
    expect(names(default_locale: :"pt-BR")).to eq(%w[en.yml pt-BR.yml])
  end

  it "adds pt-BR when available_locales includes it" do
    expect(names(available_locales: [:en, :"pt-BR"])).to eq(%w[en.yml pt-BR.yml])
  end

  it "reads available_locales given as strings" do
    expect(names(available_locales: %w[en pt-BR])).to eq(%w[en.yml pt-BR.yml])
  end

  it "returns existing files" do
    expect(described_class.locale_files(ActiveSupport::OrderedOptions.new)).to all(satisfy { |f| File.exist?(f) })
  end
end
