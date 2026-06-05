# TenancyDable v0.2.0 — Nits Delta Plan (frozen)

> **Authoritative for this run.** The gem already exists, is green at **v0.1.0**
> (`bundle exec rake` passes: 251 examples, 0 failures, 0 Standard offenses), and
> its public surface is frozen in [`.midgal/PLAN.md`](PLAN.md) + [`DESIGN.md`](../DESIGN.md).
> This run applies **three small, additive fixes** and bumps to **0.2.0**. Honor
> the original frozen contract EXCEPT where amended below. Keep the suite green at
> every phase. This is a deliberately lean 6-phase run — the changeset is small.

Branch: `nits/v0.2.0` (already checked out — do NOT switch branches; all work commits here for review, never on `master`).

## The three fixes (pinned decisions — do not redesign)

### Fix A — `ApplicationPolicy` ships the `Context` alias
**Why:** a host's `ApplicationPolicy < TenancyDable::Policy::Base` cannot resolve
`ApplicationPolicy::Context` (the constant lives in the enclosing `TenancyDable::Policy`
module, not in `Base`), so existing policy specs that say `ApplicationPolicy::Context.new(...)`
break on adoption.
**Change:** the install generator's `application_policy.rb.tt` template adds, inside
`ApplicationPolicy`, a one-line alias:
```ruby
Context = TenancyDable::Policy::Context
```
with a short comment ("so `ApplicationPolicy::Context` resolves for policy specs"),
and a commented `pundit_user` example pointing at `TenancyDable.pundit_context(...)`.
Generator-only change — no runtime lib change. (Note: the gem itself does not ship
an `ApplicationPolicy`; this is purely the generated template.)

### Fix B — host-selectable not-a-member behavior
**Why:** `Resolvable` hard-raises `TenancyDable::NotAMemberError`; a host whose
controllers already rescue `Pundit::NotAuthorizedError` (the edidable skeleton) wants
that instead, without a bespoke rescue.
**Change:** add ONE config setting, default **preserves current behavior** (additive,
non-breaking):
- `config.on_not_a_member` — accepts:
  - `:not_a_member_error` (**DEFAULT**) → raise `TenancyDable::NotAMemberError` (today's behavior),
  - `:not_authorized` → raise `Pundit::NotAuthorizedError` (require Pundit lazily at the call site; it is already a runtime dep),
  - a **callable** → run via `instance_exec` in the controller with the resolved tenant as the sole arg (`->(tenant) { ... }`), for full host control (redirect, custom error, head :forbidden).
- `Configuration#validate!` rejects a symbol that is neither known value (raise `ConfigurationError`); a callable is accepted as-is.
- `Resolvable`'s membership-missing branch dispatches on this setting instead of always raising `NotAMemberError`.
- Document the setting in the initializer template + README config table + DESIGN §4.1.

### Fix C — `CrossTenantError` is no longer dead
**Why:** the class is defined in the frozen 8-error hierarchy but never referenced;
the cross-tenant `belongs_to` validation uses a hardcoded string.
**Change (keep the class — removing it breaks the frozen 8-error contract):** give it
a single source of truth and reference it:
```ruby
class CrossTenantError < Error
  MESSAGE = "belongs to a different tenant"
end
```
and in `Scoped`'s cross-tenant validation use `errors.add(reflection.name, TenancyDable::CrossTenantError::MESSAGE)`.
(Validation still adds an error — it does NOT raise — but the class is now the
message's home, so it is no longer dead. Keep the message string identical so the
existing red-team/cross-tenant specs still pass.)

## Versioning
- Bump `TenancyDable::VERSION` `0.1.0` → **`0.2.0`** (additive new config setting = MINOR).
- Default behavior is unchanged, so no host breaks; `~> 0.1.0` pins will simply not pick it up (expected pre-1.0).
- Update `CHANGELOG.md` (`[0.2.0]`), and FOLD IN the two UPGRADING gaps the v0.1.0 review found:
  the `ApplicationPolicy::Context` alias note (Fix A) and the `rescue_from`/`on_not_a_member`
  guidance for non-members (Fix B).

## Contract impact (update DESIGN.md + spec/contract_spec.rb)
- New config setting `on_not_a_member` (default `:not_a_member_error`) — add to the
  Configuration section + the contract-lock spec's settings list (now 14 settings).
- `CrossTenantError::MESSAGE` constant — additive.
- Error count stays **8**; facade, Scoped, Resolvable signatures unchanged.

## Phase index
| # | Phase | Spec | Validates |
|---|---|---|---|
| 00 | Decision delta → DESIGN.md update | `nits/00-contract-delta.md` | DESIGN has `on_not_a_member`; suite green |
| 01 | Fix A — ApplicationPolicy alias | `nits/01-policy-alias.md` | `rspec spec/generators` |
| 02 | Fix B — on_not_a_member setting | `nits/02-not-a-member.md` | `rspec spec/resolution spec/contract_spec.rb` |
| 03 | Fix C — CrossTenantError tidy | `nits/03-cross-tenant-error.md` | `rspec spec/scoping` |
| 04 | Docs + version bump 0.2.0 | `nits/04-docs-version.md` | grep + `rspec` |
| 05 | Critic / verify | `nits/05-critic.md` | `bundle exec rake` |
