# frozen_string_literal: true

require "rails_helper"
require "tenancy_dable/job" # opt-in seam, not auto-required at boot

# Contract lock (Phase 15 hardening). `tenancy_dable`'s whole premise is a FROZEN
# public surface that derived edidable projects inherit and bump via `bundle
# update` (.midgal/PLAN.md). This spec asserts that surface — every symbol, every
# frozen default, the documented signatures — so any future drift from the
# contract fails CI here, loudly, instead of silently breaking a downstream app.
# Behavior is proven by the layer specs; this proves the SHAPE.
RSpec.describe "Frozen public contract (PLAN.md)" do
  describe "configuration settings + frozen defaults (§4.1)" do
    let(:config) { TenancyDable::Configuration.new }

    {
      tenant_model: "Tenant",
      user_model: "User",
      membership_model: "Membership",
      roles: %w[owner admin member],
      manager_roles: %w[owner admin],
      tenant_fk: :tenant_id,
      slug_param: :tenant_slug,
      require_tenant: false,
      rls: false,
      audit_overrides: :log,
      on_tenant_not_found: :raise,
      on_not_a_member: :not_a_member_error
    }.each do |setting, default|
      it "#{setting} defaults to #{default.inspect}" do
        expect(config.public_send(setting)).to eq(default)
      end
    end

    it "rls_statement defaults to a callable" do
      expect(config.rls_statement).to respond_to(:call)
    end

    it "current_user_resolver defaults to a callable" do
      expect(config.current_user_resolver).to respond_to(:call)
    end

    # Lock the surface area itself: exactly 14 host-settable settings at v0.2.0
    # (the 13 frozen at v0.1.0 plus on_not_a_member). Derived from the class's own
    # writers, so adding or removing ANY setting without updating this contract
    # fails here, loudly. Each setting is one attr_accessor → one `name=` writer.
    it "exposes exactly 14 settings (§4.1)" do
      setters = TenancyDable::Configuration.instance_methods(false).grep(/=\z/)
      expect(setters.size).to eq(14)
    end
  end

  describe "TenancyDable facade (§3)" do
    %i[
      configure configuration reset_configuration!
      current_tenant current_tenant= current_membership current_membership=
      with_tenant without_tenant pundit_context
    ].each do |method_name|
      it "responds to .#{method_name}" do
        expect(TenancyDable).to respond_to(method_name)
      end
    end

    it "pundit_context takes keywords (user:, tenant:, membership:)" do
      required = TenancyDable.method(:pundit_context).parameters
        .select { |param| param.first == :keyreq }.map(&:last)
      expect(required).to contain_exactly(:user, :tenant, :membership)
    end
  end

  describe "Current (§4.2)" do
    it "is an ActiveSupport::CurrentAttributes subclass" do
      expect(TenancyDable::Current.ancestors).to include(ActiveSupport::CurrentAttributes)
    end

    %i[tenant membership tenant_scope_disabled].each do |attr|
      it "exposes the #{attr} attribute" do
        expect(TenancyDable::Current).to respond_to(attr)
        expect(TenancyDable::Current).to respond_to(:"#{attr}=")
      end
    end
  end

  describe "Scoped model concern (§5.1)" do
    it "is an ActiveSupport::Concern" do
      expect(TenancyDable::Scoped).to be_a(ActiveSupport::Concern)
    end

    it "exposes belongs_to_tenant(name = :tenant, **opts)" do
      params = TenancyDable::Scoped::ClassMethods.instance_method(:belongs_to_tenant).parameters
      expect(params).to include([:opt, :name])
      expect(params.map(&:first)).to include(:keyrest)
    end

    it "exposes validates_uniqueness_to_tenant(*fields, **opts)" do
      params = TenancyDable::Scoped::ClassMethods.instance_method(:validates_uniqueness_to_tenant).parameters
      expect(params.map(&:first)).to include(:rest, :keyrest)
    end
  end

  describe "RelationExtension bulk-write guard (§5.2)" do
    %i[update_all delete_all destroy_all].each do |method_name|
      it "overrides ##{method_name}" do
        expect(TenancyDable::RelationExtension.instance_methods).to include(method_name)
      end
    end
  end

  describe "Identity concerns (§6)" do
    it "TenantModel#owners" do
      expect(TenancyDable::TenantModel.instance_methods).to include(:owners)
    end

    it "MembershipModel#manager?" do
      expect(TenancyDable::MembershipModel.instance_methods).to include(:manager?)
    end

    it "UserModel#membership_for / #member_of?" do
      expect(TenancyDable::UserModel.instance_methods).to include(:membership_for, :member_of?)
    end
  end

  describe "Controller::Resolvable (§9.1)" do
    it "exposes resolve_tenant!(**before_action_opts)" do
      params = TenancyDable::Controller::Resolvable::ClassMethods.instance_method(:resolve_tenant!).parameters
      expect(params.map(&:first)).to include(:keyrest)
    end

    it "overrides #default_url_options" do
      expect(TenancyDable::Controller::Resolvable.instance_methods).to include(:default_url_options)
    end
  end

  describe "Authorization (§9.2/§9.3)" do
    it "Policy::Context is a Data type of [user, tenant, membership] with #role" do
      expect(TenancyDable::Policy::Context.ancestors).to include(Data)
      expect(TenancyDable::Policy::Context.members).to eq(%i[user tenant membership])
      expect(TenancyDable::Policy::Context.instance_methods).to include(:role)
    end

    %i[index? show? create? new? update? edit? destroy?].each do |action|
      it "Policy::Base##{action} exists" do
        expect(TenancyDable::Policy::Base.instance_methods).to include(action)
      end
    end

    it "Policy::Base denies the five frozen actions by default (secure-by-default)" do
      context = TenancyDable::Policy::Context.new(user: nil, tenant: nil, membership: nil)
      policy = TenancyDable::Policy::Base.new(context, nil)
      expect([policy.index?, policy.show?, policy.create?, policy.update?, policy.destroy?])
        .to all(be(false))
    end

    it "Policy::Base::Scope#resolve exists" do
      expect(TenancyDable::Policy::Base::Scope.instance_methods).to include(:resolve)
    end
  end

  describe "Error hierarchy (§7) — 8 subclasses of TenancyDable::Error < StandardError" do
    it "Error < StandardError" do
      expect(TenancyDable::Error).to be < StandardError
    end

    %i[
      NoTenantError TenantImmutableError BulkWriteError CrossTenantError
      NotAMemberError TenantNotFoundError TenantOverrideError ConfigurationError
    ].each do |error_name|
      it "#{error_name} < TenancyDable::Error" do
        expect(TenancyDable.const_get(error_name)).to be < TenancyDable::Error
      end
    end

    # v0.2.0 additive (Fix C): CrossTenantError gained a MESSAGE constant — the
    # single source of truth for the cross-tenant belongs_to validation string,
    # so the formerly-dead class is now the message's home. Locked here (value and
    # all) as part of the frozen surface; Scoped ADDS it to errors, never raises.
    # Error count is unchanged — still the 8 classes asserted above.
    it "CrossTenantError::MESSAGE is the frozen cross-tenant validation string" do
      expect(TenancyDable::CrossTenantError::MESSAGE).to eq("belongs to a different tenant")
    end
  end

  describe "Generators (§ generators) and the Job seam (§10-I)" do
    it "defines TenancyDable::Job as a concern" do
      expect(TenancyDable::Job).to be_a(ActiveSupport::Concern)
    end

    it "ships both generator files at their contract paths" do
      %w[
        lib/generators/tenancy_dable/install/install_generator.rb
        lib/generators/tenancy_dable/model/model_generator.rb
      ].each { |path| expect(File).to exist(path) }
    end
  end
end
