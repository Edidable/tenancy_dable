# frozen_string_literal: true

require "rails_helper"
require "tenancy_dable/job" # opt-in seam, not auto-required at boot
require "tenancy_dable/channel" # opt-in seam (v0.3.0), not auto-required at boot

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
      on_not_a_member: :not_a_member_error,
      guard_reads: true,
      isolation_check: :raise,
      require_bypass_reason: false,
      audit_allowed: {},
      audit_ignored_namespaces: %w[ActiveStorage ActionText ActionMailbox SolidQueue SolidCache SolidCable]
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

    # Lock the surface area itself: exactly 19 host-settable settings (the 14 of
    # v0.4.0 plus the five of §16.7). Derived from the class's own
    # writers, so adding or removing ANY setting without updating this contract
    # fails here, loudly. Each setting is one attr_accessor → one `name=` writer.
    it "exposes exactly 19 settings (§4.1, §16.7)" do
      setters = TenancyDable::Configuration.instance_methods(false).grep(/=\z/)
      expect(setters.size).to eq(19)
    end

    it "gives each Configuration its own audit_ignored_namespaces Array, not frozen" do
      expect(config.audit_ignored_namespaces).not_to be_frozen
      expect(config.audit_ignored_namespaces).not_to equal(TenancyDable::Configuration.new.audit_ignored_namespaces)
    end
  end

  describe "TenancyDable facade (§3)" do
    %i[
      configure configuration reset_configuration!
      current_tenant current_tenant= current_membership current_membership=
      foreign_membership? with_tenant without_tenant pundit_context
      snapshot carry audit
    ].each do |method_name|
      it "responds to .#{method_name}" do
        expect(TenancyDable).to respond_to(method_name)
      end
    end

    it "without_tenant takes only the optional keyword reason: (§16.5)" do
      expect(TenancyDable.method(:without_tenant).parameters).to eq([[:key, :reason]])
    end

    it "audit takes an optional models argument (§16.3)" do
      expect(TenancyDable.method(:audit).parameters).to eq([[:opt, :models]])
    end

    it "names the without_tenant notification (§16.5)" do
      expect(TenancyDable::WITHOUT_TENANT_EVENT).to eq("without_tenant.tenancy_dable")
    end

    it "refuses a without_tenant reason that is not nil, a String or a Symbol (§16.5)" do
      [1, 1.5, true, {a: 1}, [:a], Object.new].each do |reason|
        expect { TenancyDable.without_tenant(reason: reason) { raise "must not run" } }
          .to raise_error(TenancyDable::BypassReasonError)
      end
      expect(TenancyDable.without_tenant(reason: "a String") { :ran }).to eq(:ran)
      expect(TenancyDable.without_tenant(reason: :a_symbol) { :ran }).to eq(:ran)
      expect(TenancyDable.without_tenant { :ran }).to eq(:ran)
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

    it "exposes belongs_to_tenant(name = :tenant, tag: nil, **opts)" do
      params = TenancyDable::Scoped::ClassMethods.instance_method(:belongs_to_tenant).parameters
      expect(params).to include([:opt, :name], [:key, :tag])
      expect(params.map(&:first)).to include(:keyrest)
    end

    it "exposes validates_uniqueness_to_tenant(*fields, **opts)" do
      params = TenancyDable::Scoped::ClassMethods.instance_method(:validates_uniqueness_to_tenant).parameters
      expect(params.map(&:first)).to include(:rest, :keyrest)
    end

    %i[touch update_columns delete].each do |method_name|
      it "owns ##{method_name}, the callback-free write it refuses on a foreign record (§16.2)" do
        expect(Widget.instance_method(method_name).owner).to eq(TenancyDable::Scoped)
      end
    end
  end

  describe "RelationExtension guards (§5.2, §16.1)" do
    %i[update_all delete_all destroy_all].each do |method_name|
      it "overrides ##{method_name}" do
        expect(TenancyDable::RelationExtension.instance_methods).to include(method_name)
      end
    end

    %i[pluck exists? ids load_async compute_cache_version arel].each do |method_name|
      it "overrides ##{method_name} publicly (read guard)" do
        expect(TenancyDable::RelationExtension.instance_methods).to include(method_name)
      end
    end

    %i[compute_cache_version arel].each do |method_name|
      it "hooks ##{method_name} with Active Record's own (public) visibility" do
        expect(ActiveRecord::Relation.public_method_defined?(method_name)).to be(true)
      end
    end

    %i[exec_queries perform_calculation].each do |method_name|
      it "overrides ##{method_name} privately (read guard)" do
        expect(TenancyDable::RelationExtension.private_instance_methods).to include(method_name)
        expect(TenancyDable::RelationExtension.instance_methods).not_to include(method_name)
      end
    end
  end

  describe "InsertAllExtension (§16.2)" do
    it "is prepended to ActiveRecord::InsertAll" do
      expect(ActiveRecord::InsertAll.ancestors).to include(TenancyDable::InsertAllExtension)
      expect(ActiveRecord::InsertAll.ancestors.index(TenancyDable::InsertAllExtension))
        .to be < ActiveRecord::InsertAll.ancestors.index(ActiveRecord::InsertAll)
    end

    it "keeps its guard private" do
      expect(TenancyDable::InsertAllExtension.private_instance_methods).to include(:tenancy_guard_insert_all!)
    end
  end

  describe "BuiltWithoutTenant marker (§16.1)" do
    it "is an empty module" do
      expect(TenancyDable::BuiltWithoutTenant).to be_a(Module)
      expect(TenancyDable::BuiltWithoutTenant.instance_methods).to be_empty
    end

    it "marks a relation built with no current tenant and not one built in a tenant" do
      expect(Widget.all).to be_a(TenancyDable::BuiltWithoutTenant)
      expect(TenancyDable.with_tenant(create(:tenant)) { Widget.all }).not_to be_a(TenancyDable::BuiltWithoutTenant)
    end
  end

  describe "Declarations (§16.3)" do
    %i[tenant_global tenancy_declaration tenancy_global_reason tenancy_tag].each do |method_name|
      it "ActiveRecord::Base responds to .#{method_name}" do
        expect(ActiveRecord::Base).to respond_to(method_name)
      end
    end

    it "tenant_global takes because:, tag: and allow_tenant_fk:" do
      params = ActiveRecord::Base.method(:tenant_global).parameters
      expect(params).to include([:keyreq, :because], [:key, :tag], [:key, :allow_tenant_fk])
    end

    it "Declaration is a Data type of [kind, reason, tag, allow_tenant_fk]" do
      expect(TenancyDable::Declaration.ancestors).to include(Data)
      expect(TenancyDable::Declaration.members).to eq(%i[kind reason tag allow_tenant_fk])
    end
  end

  describe "Audit (§16.3)" do
    it "lists the three finding kinds" do
      expect(TenancyDable::Audit::KINDS).to eq(%i[undeclared global_with_tenant_fk scoped_without_index])
    end

    it "Finding is a Data type of [model, kind, message]" do
      expect(TenancyDable::Audit::Finding.ancestors).to include(Data)
      expect(TenancyDable::Audit::Finding.members).to eq(%i[model kind message])
    end

    it "ships the rake task at its contract path" do
      expect(File).to exist("lib/tenancy_dable/tasks/audit.rake")
    end
  end

  describe "Snapshot (§16.4)" do
    it "is a Data type of [tenant, membership, tenant_scope_disabled] with #restore" do
      expect(TenancyDable::Snapshot.ancestors).to include(Data)
      expect(TenancyDable::Snapshot.members).to eq(%i[tenant membership tenant_scope_disabled])
      expect(TenancyDable::Snapshot.instance_methods).to include(:restore)
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

  describe "Error hierarchy (§7, §16.7) — 12 subclasses of TenancyDable::Error < StandardError" do
    it "Error < StandardError" do
      expect(TenancyDable::Error).to be < StandardError
    end

    %i[
      NoTenantError TenantImmutableError BulkWriteError CrossTenantError
      NotAMemberError TenantNotFoundError TenantOverrideError ConfigurationError
      CrossTenantReadError CrossTenantWriteError UnsafeIsolationError BypassReasonError
    ].each do |error_name|
      it "#{error_name} < TenancyDable::Error" do
        expect(TenancyDable.const_get(error_name)).to be < TenancyDable::Error
      end
    end

    # v0.2.0 additive (Fix C): CrossTenantError gained a MESSAGE constant — the
    # single source of truth for the cross-tenant belongs_to validation string,
    # so the formerly-dead class is now the message's home. Locked here (value and
    # all) as part of the frozen surface; Scoped ADDS it to errors, never raises.
    it "CrossTenantError::MESSAGE is the frozen cross-tenant validation string" do
      expect(TenancyDable::CrossTenantError::MESSAGE).to eq("belongs to a different tenant")
    end

    # v0.5.0 (§16.6): the validation messages are I18n keys with gem-shipped
    # defaults; MESSAGE stays as the compatibility constant equal to the :en one.
    it "ships the :en and :pt-BR locales on I18n.load_path with the :en default equal to MESSAGE" do
      expect(I18n.load_path.map(&:to_s)).to include(
        a_string_ending_with("lib/tenancy_dable/locale/en.yml"),
        a_string_ending_with("lib/tenancy_dable/locale/pt-BR.yml")
      )
      expect(I18n.t("errors.messages.cross_tenant", locale: :en)).to eq(TenancyDable::CrossTenantError::MESSAGE)
      expect(I18n.t("errors.messages.cross_tenant", locale: :"pt-BR")).to eq("pertence a outro tenant")
    end
  end

  describe "Railtie.locale_files (§16.6)" do
    it "returns only en.yml for an English-only i18n config" do
      config = ActiveSupport::OrderedOptions.new
      config.default_locale = :en
      config.available_locales = [:en, :fr]
      expect(TenancyDable::Railtie.locale_files(config).map { |f| File.basename(f) }).to eq(["en.yml"])
      expect(TenancyDable::Railtie.locale_files(ActiveSupport::OrderedOptions.new).map { |f| File.basename(f) }).to eq(["en.yml"])
    end

    it "adds pt-BR.yml when pt-BR is declared as the default or an available locale" do
      as_default = ActiveSupport::OrderedOptions.new
      as_default.default_locale = :"pt-BR"
      as_available = ActiveSupport::OrderedOptions.new
      as_available.available_locales = ["en", "pt-BR"]
      [as_default, as_available].each do |config|
        expect(TenancyDable::Railtie.locale_files(config).map { |f| File.basename(f) }).to eq(%w[en.yml pt-BR.yml])
      end
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

  # v0.3.0 additive: TenancyDable::Channel — the opt-in Action Cable concern, the
  # Cable parallel to Controller::Resolvable (§14.1). Like the Job seam it is NOT
  # auto-required (Action Cable stays optional), so it's required at the top of
  # this file. Locked here as part of the frozen surface: a concern exposing the
  # six FROZEN helper names a host channel inherits by including it. Locked by
  # responds-to (instance methods on the module), mirroring the Job lock — NOT an
  # exhaustive public-method match, so the necessarily-public #perform_action
  # wrapper (which Action Cable dispatches via an explicit receiver) is
  # intentionally absent from the frozen six. No new error class, no new setting.
  describe "TenancyDable::Channel seam (§14.1) — opt-in Action Cable concern" do
    it "defines TenancyDable::Channel as a concern" do
      expect(TenancyDable::Channel).to be_a(ActiveSupport::Concern)
    end

    %i[
      current_tenant current_membership tenant_member?
      reject_unless_member! stream_for_tenant with_tenant_context
    ].each do |helper|
      it "exposes ##{helper}" do
        expect(TenancyDable::Channel.instance_methods).to include(helper)
      end
    end
  end
end
