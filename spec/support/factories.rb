# frozen_string_literal: true

# Factories for the Combustion fixture models. The host models start BARE in
# Phase 01 (associations/validations arrive with the identity concerns in
# Phase 04), so these factories assign foreign keys directly and expose
# `user:` / `tenant:` / `parent:` as transient overrides — a shape that keeps
# working unchanged once the real `belongs_to` associations land.
FactoryBot.define do
  factory :tenant, class: "Tenant" do
    sequence(:slug) { |n| "tenant-#{n}" }
    sequence(:name) { |n| "Tenant #{n}" }
  end

  factory :user, class: "User" do
    sequence(:email) { |n| "user#{n}@example.test" }
  end

  factory :membership, class: "Membership" do
    role { "member" }

    transient do
      user { create(:user) }
      tenant { create(:tenant) }
    end

    user_id { user.id }
    tenant_id { tenant.id }
  end

  factory :widget, class: "Widget" do
    sequence(:name) { |n| "Widget #{n}" }

    transient do
      tenant { create(:tenant) }
      parent { nil }
    end

    tenant_id { tenant.id }
    parent_id { parent&.id }
  end
end
