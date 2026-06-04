# frozen_string_literal: true

require_relative "lib/tenancy_dable/version"

Gem::Specification.new do |spec|
  spec.name = "tenancy_dable"
  spec.version = TenancyDable::VERSION
  spec.authors = ["Lucas Guedes"]
  spec.email = ["lukaszonecell@gmail.com"]

  spec.summary = "Opinionated multi-workspace tenancy for Rails SaaS apps."
  spec.description = <<~DESC
    TenancyDable is the standards-propagation tenancy layer extracted from the
    edidable Rails SaaS skeleton. It bundles, as one versioned dependency: a
    tenant row-scoping engine (fail-closed by default, immutable tenant_id,
    bulk-write guard, ActiveJob propagation, optional Postgres RLS hook), the
    multi-workspace identity model (User <-> Membership <-> Tenant with roles),
    slug-based tenant resolution with membership enforcement, and a Pundit
    authorization Context (user + tenant + membership) plus base policy.
  DESC

  spec.homepage = "https://github.com/edidable/tenancy_dable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  # --- Runtime: framework -------------------------------------------------
  spec.add_dependency "activesupport", ">= 7.1", "< 9"
  spec.add_dependency "activerecord", ">= 7.1", "< 9"
  spec.add_dependency "actionpack", ">= 7.1", "< 9"
  spec.add_dependency "railties", ">= 7.1", "< 9"

  # --- Runtime: authorization layer (Pundit Context + base policy) --------
  spec.add_dependency "pundit", ">= 2.3"

  # --- Runtime: row-scoping engine ---------------------------------------
  # DECIDED (see .midgal/PLAN.md): the scoping engine is SELF-CONTAINED in this
  # gem — fail-closed default scope, immutable tenant_id, bulk-write guard,
  # ActiveJob propagation, and an optional Postgres RLS hook all live here. We
  # deliberately do NOT depend on acts_as_tenant / rails-tenantify; their
  # patterns are referenced, not imported, so this foundation owns its own
  # security boundary with no third-party bus-factor.

  # --- Development --------------------------------------------------------
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "standard", "~> 1.40"
  spec.add_development_dependency "combustion", "~> 1.5"
  spec.add_development_dependency "sqlite3", ">= 1.6"
end
