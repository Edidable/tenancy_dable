# frozen_string_literal: true

require "spec_helper" # pure-lib: Configuration#validate! touches neither DB nor Rails

# `Configuration#validate!` is the configuration gate `TenancyDable.configure`
# runs after the host's block (DESIGN.md §4.1). This spec locks the ONE branch
# the v0.2.0 delta added — the `on_not_a_member` guard (Fix B) — adversarially:
# every accepted form passes, and a symbol outside the known set is rejected with
# `ConfigurationError`. (The setting's runtime *behavior* is proven separately in
# spec/resolution/not_a_member_behavior_spec.rb; here we prove only that misuse is
# caught at configure time, before a single request runs.)
RSpec.describe TenancyDable::Configuration do
  subject(:config) { described_class.new }

  describe "#validate! — on_not_a_member (v0.2.0)" do
    # A fresh Configuration is valid out of the box, so each example below isolates
    # the on_not_a_member axis: only that setting changes, nothing else can fail.
    it "accepts the default :not_a_member_error" do
      config.on_not_a_member = :not_a_member_error
      expect { config.validate! }.not_to raise_error
    end

    it "accepts :not_authorized" do
      config.on_not_a_member = :not_authorized
      expect { config.validate! }.not_to raise_error
    end

    it "accepts a callable (host-supplied handler), as-is" do
      config.on_not_a_member = ->(tenant) { tenant }
      expect { config.validate! }.not_to raise_error
    end

    it "rejects a symbol outside the known set with ConfigurationError" do
      config.on_not_a_member = :redirect_somewhere # not a recognized mode

      expect { config.validate! }
        .to raise_error(TenancyDable::ConfigurationError, /on_not_a_member/)
    end

    it "returns self on success, so configure can chain on it" do
      expect(config.validate!).to be(config)
    end
  end
end
