# Phase 04 — Identity Concerns (Tenant / Membership / User)

**Read `.midgal/PLAN.md` + `DESIGN.md`.** Verify Phase 02 (config/current) exists.

## Files
- `lib/tenancy_dable/models/tenant_model.rb` — `has_many :memberships, dependent: :destroy`, `has_many :users, through:`; slug presence/uniqueness/format + `before_validation` generation with collision suffix; `#owners`.
- `lib/tenancy_dable/models/membership_model.rb` — `belongs_to :user, :tenant`; `validates :role, inclusion: {in: config.roles}`; `validates :user_id, uniqueness: {scope: :tenant_id}`; role predicates generated from `config.roles`; scopes `owners`, `admins` (manager_roles); `before_update` last-owner-demotion guard (`throw :abort`); `#manager?`. **Document inline that this concern deliberately does NOT include `Scoped`** (it is queried before the active tenant is known).
- `lib/tenancy_dable/models/user_model.rb` — `has_many :memberships, dependent: :destroy`, `has_many :tenants, through:`; `#membership_for(tenant)`, `#member_of?(tenant)`.
- Mix the three concerns into the Combustion `Tenant`/`Membership`/`User` models.

## Acceptance
- Role predicates derive from config (not hard-coded).
- Last-owner demotion is blocked; non-last owner demotion allowed.
- `membership_for`/`member_of?` return correctly.

## Validation
`bundle exec standardrb` + `bundle exec rspec` (smoke green).

## On completion
Scratchpad: role-predicate generation + the last-owner guard semantics.
