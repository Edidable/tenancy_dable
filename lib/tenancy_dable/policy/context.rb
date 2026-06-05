# frozen_string_literal: true

module TenancyDable
  module Policy
    # The authorization subject every policy decides on: the acting user PLUS the
    # workspace they are acting in and their membership in it. Policies (and
    # `policy_scope`) receive this triple, never a bare user — the same user is an
    # owner in one tenant and a non-member in another, so identity alone cannot
    # answer "may they?" (DESIGN.md §9.2).
    #
    # A pure value object: a frozen `Data` type with NO ActiveRecord dependency
    # (DESIGN.md §2), built by `TenancyDable.pundit_context(user:, tenant:,
    # membership:)` and handed to Pundit in place of the user.
    Context = Data.define(:user, :tenant, :membership) do
      # The acting role for this request, read from the membership; nil when there
      # is no membership (a non-member, or no tenant in context). `Base#role`
      # delegates here so the role has a single source of truth.
      def role
        membership&.role
      end
    end
  end
end
