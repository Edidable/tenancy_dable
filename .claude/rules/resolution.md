---
paths:
  - "lib/tenancy_dable/controller/**"
  - "lib/tenancy_dable/channel.rb"
  - "spec/resolution/**"
  - "spec/integration/resolution_and_policy_spec.rb"
  - "spec/channels/**"
---
Resolve the tenant by `params[slug_param]` and `slug` only; never read or trust a tenant id from a URL or a subscription param. Proof: `spec/resolution/slug_only_spec.rb`, `spec/channels/tenant_channel_spec.rb`.
Keep the step order: find tenant, resolve user via `current_user_resolver` (`instance_exec`), `membership_for`, then publish through the facade (`TenancyDable.current_tenant=`, never `Current` directly).
A non-member never gets a published tenant, in every `on_not_a_member` mode (`:not_a_member_error`, `:not_authorized`, a callable): the before_action returns before publishing. Proof: `spec/resolution/membership_enforcement_spec.rb`, `spec/resolution/not_a_member_behavior_spec.rb`.
`:not_authorized` requires Pundit lazily inside the branch; do not add a top-level `require "pundit"` to the controller concern.
A callable `on_not_a_member` is `instance_exec`'d in the controller with the tenant as its only argument.
`on_tenant_not_found`: `:raise` uses `find_by!` (`RecordNotFound`), `:null` uses `find_by`, publishes a cleared context and skips membership; the action then runs with no tenant, which is fail-open unless `require_tenant` is on. Proof: `spec/resolution/tenant_not_found_spec.rb`.
`default_url_options` merges on top of `super`, adds nothing when no tenant is current, and reads `slug_param` live. Proof: `spec/resolution/default_url_options_spec.rb`.
The concern is installed by prepend (the railtie); changing it to an include silently loses `default_url_options`. See `.claude/rules/boot.md`.
Do not assume Devise or any auth stack in the concern; the resolved user only has to answer `membership_for`.
The Cable concern is opt-in: never require `tenancy_dable/channel` from `lib/tenancy_dable.rb`, and never name an Action Cable constant in it.
Cable resolves with non-bang `find_by` and rejects; it does not consult `on_tenant_not_found`. A nil tenant means a nil membership means rejection.
`perform_action` in the Cable concern must stay public (Action Cable calls it with an explicit receiver); the helper list is locked by `spec/contract_spec.rb`.
`stream_for_tenant` names the stream `tenant:<id>[:suffix]`; call it only after membership is confirmed.
If you change a resolution step or a Cable helper, also update `DESIGN.md` §9.1 and §14.1 pointers, `README.md`, the harness fixtures (`spec/internal/app/controllers/widgets_controller.rb`, `spec/internal/app/channels/tenant_channel.rb`) and `spec/contract_spec.rb`.
Narrative: docs/domains/resolution.md
