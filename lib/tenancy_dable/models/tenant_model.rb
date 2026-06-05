# frozen_string_literal: true

require "active_support/concern"

module TenancyDable
  # Identity concern for the workspace/tenant model (default `Tenant`). The host
  # mixes it in (`include TenancyDable::TenantModel`); the railtie makes the file
  # available on `:active_record` load (DESIGN.md §2/§6.1).
  #
  # It wires the membership/user graph, guarantees every tenant has a unique,
  # URL-safe slug (the key slug resolution looks up — Phase 05), and exposes the
  # workspace's owners. Association class names are read from the configuration so
  # a host that renames its models (`config.membership_model`, `config.user_model`)
  # still gets a correctly-wired graph.
  module TenantModel
    extend ActiveSupport::Concern

    # A slug is lowercase alphanumerics joined by single hyphens, with no leading
    # or trailing hyphen — exactly what `generate_slug` produces and what is safe
    # to drop into a `/:tenant_slug/...` URL.
    SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    included do
      has_many :memberships,
        class_name: TenancyDable.configuration.membership_model,
        dependent: :destroy
      # Source association (`:user`) is inferred from the singularized name and is
      # stable even when the user model is renamed (only its class changes).
      has_many :users, through: :memberships

      # Presence + uniqueness always run; the format check is skipped when the
      # value is blank so `presence` owns the "missing slug" message rather than
      # both firing. (A single `validates ..., allow_blank: true` would wrongly
      # let `presence` pass on a blank slug, so they are split.)
      validates :slug, presence: true, uniqueness: true
      validates :slug,
        format: {with: SLUG_FORMAT, message: "must be lowercase letters, numbers, and single hyphens"},
        allow_blank: true

      before_validation :generate_slug
    end

    # The User records who hold the owner role (the highest-ranked role,
    # `config.roles.first`) in this tenant. Returns a relation, via a subquery on
    # this tenant's memberships, so it composes and is robust to a renamed
    # membership/user model.
    def owners
      TenancyDable.configuration.user_class.where(
        id: memberships.where(role: TenancyDable.configuration.roles.first).select(:user_id)
      )
    end

    private

    # Assign a unique slug when one was not supplied. Runs on every save but
    # no-ops once a slug is present, so an explicitly-set slug is never rewritten
    # (its shape is still enforced by the format validation above).
    def generate_slug
      return if slug.present?

      base = normalize_slug(slug_source)
      return if base.blank? # nothing to slugify — `presence` will flag it

      self.slug = unique_slug(base)
    end

    # The human label a slug is derived from. `tenants.name` is a test-support /
    # convenience column (DESIGN.md §10-H) and not contract-guaranteed, so a host
    # without it simply must supply the slug itself (caught by `presence`).
    def slug_source
      respond_to?(:name) ? name : nil
    end

    # Fold any input into a strict, URL-safe slug. `parameterize` transliterates
    # accents and turns runs of punctuation/space into hyphens but PRESERVES
    # underscores, so we additionally fold those into hyphens, collapse repeats,
    # and trim the edges — guaranteeing the result matches SLUG_FORMAT.
    def normalize_slug(value)
      value.to_s.parameterize.tr("_", "-").squeeze("-").gsub(/\A-|-\z/, "")
    end

    # `base`, then `base-2`, `base-3`, ... until one is free. The DB unique index
    # is the ultimate guard against the (test-irrelevant) check-then-insert race.
    def unique_slug(base)
      candidate = base
      counter = 2
      while slug_taken?(candidate)
        candidate = "#{base}-#{counter}"
        counter += 1
      end
      candidate
    end

    # Is `candidate` already used by another tenant? `where.not(id: id)` excludes
    # self on update; for a new record (id nil) it compiles to `id IS NOT NULL`,
    # i.e. every persisted row — exactly the set we want to check against.
    def slug_taken?(candidate)
      self.class.where(slug: candidate).where.not(id: id).exists?
    end
  end
end
