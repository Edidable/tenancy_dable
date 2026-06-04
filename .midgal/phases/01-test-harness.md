# Phase 01 — Test Harness (Combustion)

**Read `.midgal/PLAN.md` + `DESIGN.md` first.** Verify both exist before starting.

## Objective
Stand up a Combustion-backed Rails test app so specs can boot the gem against real ActiveRecord/ActionPack.

## Tasks
1. Add dev deps to the gemspec if missing: `rails` (>= 7.1, < 9), `rspec-rails`, `combustion`, `sqlite3`. Run `bundle install`.
2. `spec/internal/` Combustion app: `config/database.yml` (sqlite memory), `db/schema.rb` with the fixture schema from `DESIGN.md` (`tenants`, `users`, `memberships`, `widgets`), `config/routes.rb`, `config/application.rb`, and minimal `app/models` (`Tenant`,`User`,`Membership`,`Widget`) — left bare for now; later phases mix the concerns in.
3. `spec/rails_helper.rb` boots Combustion with ActiveRecord + ActionController; `spec/spec_helper.rb` stays lib-only.
4. `spec/support/factories.rb` (plain FactoryBot or fixtures): tenant (with slug), user, membership (roles), widget.
5. Shared contexts `"with tenant"` (sets `TenancyDable.current_tenant`) and `"with authenticated user"` — stub now, wired as facade lands in Phase 02 (guard with `respond_to?`).
6. Keep the existing smoke spec green.

## Acceptance / Validation
- `bundle exec rspec` boots Combustion and passes (smoke + a trivial schema sanity spec).

## On completion
Scratchpad: harness layout + how to run a single area's specs.
