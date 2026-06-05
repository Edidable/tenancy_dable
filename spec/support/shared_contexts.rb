# frozen_string_literal: true

# Shared contexts for the tenancy specs.
#
# The TenancyDable facade methods these target (`current_tenant=`,
# `current_user_resolver=`) land in Phase 02. To stay green TODAY, every facade
# call is guarded with `respond_to?`: until the facade exists the contexts
# simply make a `tenant` / `user` record available and no-op the wiring; once it
# exists, including a context actually establishes the current tenant / acting
# user. Later phases flesh these out (e.g. wiring membership + resolution).

RSpec.shared_context "with tenant" do
  let(:tenant) { create(:tenant) }

  before do
    TenancyDable.current_tenant = tenant if TenancyDable.respond_to?(:current_tenant=)
  end

  # No local teardown: rails_helper's global `after` resets `Current` (and the
  # configuration) after every example, side-effect-free.
end

RSpec.shared_context "with authenticated user" do
  let(:user) { create(:user) }

  before do
    # The acting user is auth-agnostic: resolved via
    # `TenancyDable.configuration.current_user_resolver` (default reads
    # `Current.user`). Resolvable (Phase 05) runs that resolver with `instance_exec`
    # in the controller's context (DESIGN §9.1), which REBINDS `self` — so the stub
    # must NOT lean on an implicit-self `let` (`-> { user }` would dispatch `user`
    # to the controller and blow up). Capture the record in a LOCAL, which resolves
    # the same no matter what `self` is.
    acting_user = user
    config = TenancyDable.configuration if TenancyDable.respond_to?(:configuration)
    if config.respond_to?(:current_user_resolver=)
      config.current_user_resolver = -> { acting_user }
    end
  end
end
