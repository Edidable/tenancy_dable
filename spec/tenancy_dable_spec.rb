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

  describe "constants" do
    it "names the without_tenant event" do
      expect(TenancyDable::WITHOUT_TENANT_EVENT).to eq("without_tenant.tenancy_dable")
    end

    it "keeps the gem's directory out of the public constants" do
      expect { TenancyDable::LIB_DIR }.to raise_error(NameError)
    end
  end
end
