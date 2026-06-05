# NITS_REPORT — v0.2.0 critic / final gate

**Phase 05 (final adversarial + consistency pass).** Date: 2026-06-05.
Branch: `nits/v0.2.0` (all work here — **never** master).
Verdict: **PASS.** All three fixes proven, gate green, no regressions, contract consistent.

---

## 1. Full gate — GREEN

`bundle exec rake` (default task = `%i[spec standard]`) → **exit 0**.

- **RSpec:** `266 examples, 0 failures`.
- **Standard:** 0 offenses (`bundle exec standardrb` → exit 0; rake aborts on first
  failing task, so exit 0 across the chain confirms both).

Suite grew from **260 → 266**: this phase added 6 examples (5 in a new
`spec/configuration_spec.rb`, 1 contract lock in `spec/contract_spec.rb`). The
v0.1.0 baseline was 251; the v0.2.0 delta nets **+15**.

---

## 2. Fix A — `ApplicationPolicy` ships the `Context` alias — PROVEN

- **Template:** `lib/generators/tenancy_dable/install/templates/application_policy.rb.tt:24`
  → `Context = TenancyDable::Policy::Context`, with a comment explaining why
  (`ApplicationPolicy::Context` must resolve for host policy specs) and a
  commented `pundit_user` example pointing at `TenancyDable.pundit_context(...)`.
- **Spec asserts it:** `spec/generators/install_generator_spec.rb:64-68`
  ("aliases Context on the generated ApplicationPolicy…") renders the real
  template into a throwaway dir and asserts the string is present.
- **Generator-only:** the gem ships no `ApplicationPolicy` (`grep` finds the alias
  only in the `.tt` template), so no runtime lib changed — matches the pinned decision.
- **Bonus (rendered-template constant resolution):** not added. The string-match
  proof + the contract lock that `Policy::Context` is a `Data` type of
  `[user, tenant, membership]` with `#role` (`contract_spec.rb:135-139`) together
  prove both that the alias text is emitted and that its target exists and is
  correct. Eval-loading a real top-level `ApplicationPolicy` into the suite would
  pollute the global namespace for marginal gain; declined deliberately.

## 3. Fix B — host-selectable `on_not_a_member` — PROVEN

- **Setting + default:** `configuration.rb:29,49` → `on_not_a_member` defaults to
  `:not_a_member_error` (preserves v0.1.0 behavior; additive ⇒ MINOR bump).
- **Dispatch:** `resolvable.rb:94-105` (`tenancy_dable_handle_not_a_member`)
  branches: `:not_a_member_error` → `raise NotAMemberError`; `:not_authorized` →
  lazy `require "pundit"` then `raise Pundit::NotAuthorizedError`; else
  `instance_exec(tenant, &setting)` in the controller. Every branch `return`s
  without publishing — a non-member never gets a published tenant (invariant 2 holds).
- **All three modes behave** — `spec/resolution/not_a_member_behavior_spec.rb`
  (all green):
  - default → `TenancyDable::NotAMemberError`;
  - `:not_authorized` → `Pundit::NotAuthorizedError`;
  - callable → runs in controller ctx, receives the resolved tenant, its
    `head :forbidden` wins (403, no body leak); a callable may also raise its own
    error, which propagates;
  - contrast: a genuine member is still admitted under any mode.
- **`validate!` rejects an unknown symbol** — **gap closed this phase.** `validate!`
  had **zero** test coverage anywhere. Added `spec/configuration_spec.rb`:
  rejects `:redirect_somewhere` with `ConfigurationError` matching `/on_not_a_member/`
  (`configuration.rb:101-104`); accepts `:not_a_member_error`, `:not_authorized`,
  and a callable as-is; returns `self` on success.
- **Default path = byte-for-byte old behavior:** the pre-existing
  `spec/resolution/membership_enforcement_spec.rb` (4 `NotAMemberError` examples)
  still passes unchanged — no regression.

## 4. Fix C — `CrossTenantError` is no longer dead — PROVEN

- **Constant exists:** `errors.rb:30-32` → `class CrossTenantError < Error;
  MESSAGE = "belongs to a different tenant"; end`.
- **`Scoped` references it:** `scoped.rb:120` →
  `errors.add(reflection.name, TenancyDable::CrossTenantError::MESSAGE)`.
  Validation **adds** the error — it does not raise (per the pinned decision).
- **String unchanged & single source:** `grep -rn "belongs to a different tenant"
  lib/` returns **exactly one** hit — the constant definition (`errors.rb:31`).
  No hardcoded literal remains anywhere else in `lib/`.
- **Specs pass:** `spec/scoping/cross_tenant_spec.rb` (4 examples, incl. a
  dedicated "sources the validation message from `CrossTenantError::MESSAGE`")
  plus the red-team association invariant — all green.

## 5. Security invariants — NO REGRESSION

`bundle exec rspec spec/security/red_team_spec.rb` → **9 examples, 0 failures**
(exit 0). All six invariants covered: 1 fail-closed-raises, 2 no-cross-tenant-read
(direct / bulk / association), 3 tenant_id immutable, 4 Pundit scope fails closed,
5 slug-only resolution, 6 audit logs ids-only.

## 6. Contract consistency — CONFIRMED

- **Settings = 14:** `contract_spec.rb:47-50` asserts exactly 14 host-settable
  settings (derived from the class's own `name=` writers); `on_not_a_member`
  default `:not_a_member_error` locked at `:28`.
- **New constant reflected:** added `contract_spec.rb` lock —
  `CrossTenantError::MESSAGE == "belongs to a different tenant"` — so the additive
  constant (and its exact value) is now part of the frozen surface.
- **Error count still 8:** `contract_spec.rb:164-171` lists the 8 subclasses;
  no error added or removed.
- **Version 0.2.0:** `lib/tenancy_dable/version.rb:4` → `VERSION = "0.2.0"`;
  `CHANGELOG.md:14` → `## [0.2.0] - 2026-06-05` with matching compare/tag link refs.
- **Docs coherent:** `on_not_a_member` documented in the initializer template
  (`initializer.rb.tt:55`), README config table, DESIGN §4.1 table + §13, CHANGELOG,
  and UPGRADING; `CrossTenantError::MESSAGE` documented in DESIGN §4.2/§5.1; the
  CHANGELOG's `DESIGN.md#13…` anchor matches the actual §13 heading.

---

## 7. Critic-phase additions (this phase)

| File | Change | Closes |
|---|---|---|
| `spec/configuration_spec.rb` (new) | 5 examples proving `Configuration#validate!`'s `on_not_a_member` guard — rejects unknown symbol, accepts both known symbols + callable, returns self | task 3 ("`validate!` rejects an unknown symbol") — previously untested |
| `spec/contract_spec.rb` | +1 example locking `CrossTenantError::MESSAGE` value | task 6 ("contract_spec reflects … the new constant") |

Both pure additions; no production code touched in the critic phase. Re-ran the
full gate after both → still `266 examples, 0 failures`, 0 Standard offenses.

## 8. Branch / commit

All v0.2.0 work lives on **`nits/v0.2.0`** (verified `git rev-parse
--abbrev-ref HEAD`), committed for review — **not** on master. 17 files in the
delta: 6 production/template files (errors, scoped, configuration, resolvable,
version, application_policy.tt + initializer.tt), 4 specs (contract, install
generator, cross_tenant, + new configuration & not_a_member_behavior), and the
docs (DESIGN, README, CHANGELOG, UPGRADING, FINAL_REPORT) + this report.

**Final verdict: v0.2.0 nits delta is correct, proven, and green. Ship for review.**
