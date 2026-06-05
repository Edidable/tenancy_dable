# frozen_string_literal: true

require "rails_helper"

# Phase 15 adversarial gate (.midgal/phases/15-critic-hardening.md). Instead of
# pinning one branch of one unit like the layer specs, this file plays attacker:
# every example TRIES to break tenant isolation and asserts the breach is refused.
# It deliberately attacks vectors the per-layer specs do NOT cover (every read
# entry point at once, the `unscoped` bulk-write escape, the mass-assign fk path,
# a poisoned `.none` chain, and the audit log's payload surface), so it adds
# coverage rather than restating it.
#
# Invariant -> primary proving spec (full map in FINAL_REPORT.md):
#   1 fail-closed              spec/scoping/default_scope_spec.rb        (+ below)
#   2 no cross-tenant read     spec/scoping/{default_scope,cross_tenant,bulk_write_guard}_spec.rb,
#                              spec/integration/cross_tenant_isolation_spec.rb (+ below)
#   3 tenant_id immutable      spec/scoping/tenant_assignment_spec.rb    (+ below)
#   4 pundit scope none        spec/policy/scope_spec.rb                 (+ below)
#   5 slug-only resolution     spec/resolution/slug_only_spec.rb        (+ below)
#   6 no PII/secret in logs    (no prior unit spec — CLOSED HERE)
RSpec.describe "Red-team: tenant isolation cannot be broken" do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  describe "invariant 1 — fail-closed actually RAISES, never a silent `all`" do
    it "raises NoTenantError at every read entry point, leaking no rows" do
      # Rows exist; with require_tenant armed and no tenant, the guard must hide
      # them by RAISING, not by returning them. Build BEFORE arming the flag — an
      # armed default scope raises even on Widget.new.
      create(:widget, tenant: tenant_a)
      create(:widget, tenant: tenant_b)
      TenancyDable.configure { |c| c.require_tenant = true }

      aggregate_failures "every query path is fail-closed" do
        expect { Widget.all.to_a }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.count }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.first }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.last }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.pluck(:id) }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.exists? }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.find_by(name: "anything") }.to raise_error(TenancyDable::NoTenantError)
        expect { Widget.where(name: "anything").to_a }.to raise_error(TenancyDable::NoTenantError)
      end
    end
  end

  describe "invariant 2 — no cross-tenant read path (three ways, all blocked)" do
    it "(direct query) cannot reach another tenant's rows while acting in A" do
      mine = create(:widget, tenant: tenant_a, name: "A-1")
      secret = create(:widget, tenant: tenant_b, name: "B-secret")

      TenancyDable.with_tenant(tenant_a) do
        expect { Widget.find(secret.id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(Widget.where(id: secret.id).to_a).to be_empty
        # even explicitly asking for B's id: the tenant filter is ANDed in
        expect(Widget.where(tenant_id: tenant_b.id).to_a).to be_empty
        expect(Widget.all.to_a).to contain_exactly(mine)
        expect(Widget.pluck(:tenant_id).uniq).to eq([tenant_a.id])
      end
    end

    it "(association) cannot reference a record owned by another tenant" do
      parent_in_b = create(:widget, tenant: tenant_b)
      child = build(:widget, tenant: tenant_a, parent: parent_in_b)

      expect(child).not_to be_valid
      expect(child.errors[:parent]).to include("belongs to a different tenant")
    end

    it "(bulk write) cannot escape the current tenant — including via `unscoped`" do
      create(:widget, tenant: tenant_b, name: "B-keep")

      # no current tenant at all -> refused
      expect { Widget.update_all(name: "hacked") }
        .to raise_error(TenancyDable::BulkWriteError)

      TenancyDable.with_tenant(tenant_a) do
        # explicitly targeting B's rows -> refused (relation not pinned to A)
        expect { Widget.where(tenant_id: tenant_b.id).delete_all }
          .to raise_error(TenancyDable::BulkWriteError)
        # escape attempt via `unscoped` (strips the default scope) -> still refused
        expect { Widget.unscoped.update_all(name: "hacked") }
          .to raise_error(TenancyDable::BulkWriteError)
      end

      # B's row survived every attempt, untouched
      survivor = TenancyDable.without_tenant { Widget.find_by(name: "B-keep") }
      expect(survivor).to be_present
    end
  end

  describe "invariant 3 — tenant_id is immutable after create" do
    it "refuses every reassignment path on a persisted record" do
      widget = create(:widget, tenant: tenant_a)

      # 1. the fk writer (record.tenant_id = x)
      expect { widget.tenant_id = tenant_b.id }
        .to raise_error(TenancyDable::TenantImmutableError)

      # 2. the association writer (record.tenant = other), caught at save by the
      #    before_update backstop
      via_assoc = Widget.unscoped.find(widget.id)
      via_assoc.tenant = tenant_b
      expect { via_assoc.save! }.to raise_error(TenancyDable::TenantImmutableError)

      # 3. mass-assignment (update!(tenant_id: x))
      via_mass = Widget.unscoped.find(widget.id)
      expect { via_mass.update!(tenant_id: tenant_b.id) }
        .to raise_error(TenancyDable::TenantImmutableError)

      # the row never moved tenants
      expect(Widget.unscoped.find(widget.id).tenant_id).to eq(tenant_a.id)
    end
  end

  describe "invariant 4 — Pundit scope fails closed (scope.none)" do
    let(:scope_class) { TenancyDable::Policy::Base::Scope }

    def context_for(tenant)
      TenancyDable.pundit_context(user: build(:user), tenant: tenant, membership: nil)
    end

    it "returns a none-relation that no further chaining can re-open" do
      real = create(:widget, tenant: tenant_a)

      resolved = TenancyDable.without_tenant do
        scope_class.new(context_for(nil), Widget.all).resolve
      end

      # `.none` truly poisons the chain — re-asking for the known row stays empty
      expect(resolved.to_a).to be_empty
      expect(resolved.count).to eq(0)
      expect(resolved.exists?).to be(false)
      expect(resolved.where(id: real.id).to_a).to be_empty
    end
  end

  describe "invariant 5 — slug-only resolution (never trust a URL id)" do
    # Full request-level proof: spec/resolution/slug_only_spec.rb. This pins the
    # structural reason — the ONLY lookup key Resolvable uses is the slug
    # (DESIGN.md §9.1), so a numeric id in the slug slot resolves to nothing.
    it "never resolves a tenant by its numeric id placed in the slug slot" do
      tenant = create(:tenant, slug: "acme")
      lookup = TenancyDable.configuration.tenant_class

      expect(lookup.find_by(slug: tenant.slug)).to eq(tenant)
      expect(lookup.find_by(slug: tenant.id.to_s)).to be_nil
      expect(lookup.find_by(slug: tenant.id)).to be_nil
    end
  end

  describe "invariant 6 — audit logs carry tenant ids ONLY, never payload/PII" do
    it "logs only ids on an override, even when the tenants carry names and slugs" do
      a = create(:tenant, name: "Acme Payroll Secrets", slug: "acme-payroll")
      b = create(:tenant, name: "Globex Trade Secrets", slug: "globex-trade")

      fake_logger = instance_double(Logger)
      allow(fake_logger).to receive(:warn)
      allow(TenancyDable).to receive(:logger).and_return(fake_logger)

      TenancyDable.current_tenant = a # nil -> A: establish, no override, no log
      TenancyDable.current_tenant = b # A -> B: override -> logs exactly once

      expect(fake_logger).to have_received(:warn).once do |line|
        expect(line).to include("##{a.id}", "##{b.id}")
        expect(line).not_to include(
          "Acme Payroll Secrets", "Globex Trade Secrets",
          "acme-payroll", "globex-trade"
        )
      end
    end

    it "names only ids in the raise-mode override error, never payload" do
      TenancyDable.configure { |c| c.audit_overrides = :raise }
      a = create(:tenant, name: "Acme Payroll", slug: "acme")
      b = create(:tenant, name: "Globex Trade", slug: "globex")
      TenancyDable.current_tenant = a

      expect { TenancyDable.current_tenant = b }
        .to raise_error(TenancyDable::TenantOverrideError) { |error|
          expect(error.message).to include("##{a.id}", "##{b.id}")
          expect(error.message).not_to include("Acme Payroll", "Globex Trade", "acme", "globex")
        }
    end
  end
end
