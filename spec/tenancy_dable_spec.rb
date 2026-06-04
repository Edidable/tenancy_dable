# frozen_string_literal: true

RSpec.describe TenancyDable do
  it "has a version number" do
    expect(TenancyDable::VERSION).not_to be_nil
  end

  describe ".configure" do
    after { TenancyDable.reset_configuration! }

    it "yields the configuration object" do
      expect { |b| TenancyDable.configure(&b) }
        .to yield_with_args(TenancyDable::Configuration)
    end

    it "memoizes a single configuration instance" do
      expect(TenancyDable.configuration).to be(TenancyDable.configuration)
    end
  end
end
