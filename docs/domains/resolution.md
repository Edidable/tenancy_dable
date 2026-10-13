# Resolution

Resolution turns a URL slug into a published tenant and membership for the length of a request, and the opt-in Cable concern does the same for a channel subscription. The code is [FILE:lib/tenancy_dable/controller/resolvable.rb] and [FILE:lib/tenancy_dable/channel.rb]; the specs are under [FILE:spec/resolution/] and [FILE:spec/channels/].

## Overview

The concern [MODULE:TenancyDable::Controller::Resolvable] is prepended onto [CLASS:ActionController::Base] by the railtie (see `docs/domains/boot.md` for why it is a prepend). A controller opts in with the class macro [METHOD:resolve_tenant!], which installs one [METHOD:before_action] named [METHOD:tenancy_dable_resolve_tenant]; every option the macro receives (`only:`, `except:`, `if:`, `unless:`, `prepend:`) passes straight through to [METHOD:before_action], and [SPEC:spec/contract_spec.rb] locks the macro's keyword signature. A controller that never calls the macro is untouched, except that the prepended [METHOD:default_url_options] is present on it and stays inert while no tenant is current.

The [METHOD:before_action] runs four steps in this order, every one driven by the slug:

1. It finds the tenant by slug, honoring [CONFIG:on_tenant_not_found].
2. It resolves the acting user by running [CONFIG:current_user_resolver] with [METHOD:instance_exec] in the controller, so a host resolver can call controller helpers such as `current_user`.
3. It asks the user for [METHOD:membership_for] the tenant; a missing user or a missing membership dispatches on [CONFIG:on_not_a_member] and returns without publishing anything.
4. It publishes [METHOD:TenancyDable.current_tenant=] and [METHOD:TenancyDable.current_membership=] through the facade, so the audit-override policy, the isolation check and the RLS hook apply as they do to any other write.

[SPEC:spec/resolution/successful_resolution_spec.rb] proves the published tenant and the acting user's own membership (not another member's), and that the executor clears both once the response is sent.

## Principles

[RULE:Resolution is slug-only]. The tenant is looked up by [COLUMN:slug] from [PARAM:the slug_param entry of params] and never by id, so a numeric id placed in the slug position is just a slug that matches nothing. [SPEC:spec/resolution/slug_only_spec.rb] proves it for both [CONFIG:on_tenant_not_found] strategies, and [SPEC:spec/channels/tenant_channel_spec.rb] proves it for a subscription.

[RULE:Membership is required to enter a workspace]. A user who belongs to no workspace, a user who belongs only to a different tenant, and a request with no acting user at all are all non-members of the resolved tenant, and none of them gets a published tenant. [SPEC:spec/resolution/membership_enforcement_spec.rb] proves the three cases and a genuine member as the contrast.

[RULE:Resolution is auth-agnostic]. The gem reads the acting user only through [CONFIG:current_user_resolver]; the default reads the host's top-level [CONST:Current.user] when it exists and answers nil otherwise. Nothing assumes Devise, Warden or any session store, and the resolved user must respond to [METHOD:membership_for] (the user identity concern provides it; see `docs/domains/identity.md`).

[RULE:The slug is injected into generated URLs]. [METHOD:default_url_options] merges [CONFIG:slug_param] with the current tenant's slug on top of whatever the framework or a host override higher in the ancestry returns, and contributes no key when no tenant is current. A path helper nested under the host's `/:tenant_slug` scope can therefore omit the slug. [SPEC:spec/resolution/default_url_options_spec.rb] proves the injection, the custom [CONFIG:slug_param] name, the inert case and the path-helper integration.

## Unknown slug

[CONFIG:on_tenant_not_found] has two strategies. With [VALUE:raise] (the default) the lookup uses [METHOD:find_by!], so a miss raises [ERROR:ActiveRecord::RecordNotFound], which Rails renders as a 404 in production. With [VALUE:null] the lookup uses [METHOD:find_by], a miss leaves the request workspace-less, and the before_action publishes a cleared tenant and membership without consulting the user or requiring membership, because there is no workspace to be a member of. [SPEC:spec/resolution/tenant_not_found_spec.rb] proves both strategies, including that the null path does not require membership.

### Gotcha: `:null` runs the action with no tenant

[SYMPTOM:with `on_tenant_not_found = :null`, a scoped read in the action of an unknown slug returns every tenant's rows and raises nothing]. [CAUSE:the before_action publishes a cleared tenant and the action continues, so the default scope takes its fail-open branch when [CONFIG:require_tenant] is off]. [FIX:set `require_tenant`, or keep scoped reads out of workspace-less actions]. [RULE:a host that uses `:null` turns `require_tenant` on or never reads a scoped model in a workspace-less action; the same holds for a controller that never calls `resolve_tenant!`].

## A user who is not a member

[CONFIG:on_not_a_member] decides what happens when step 3 finds no membership. In every mode the before_action returns without publishing, so a non-member never holds a tenant:

- [VALUE:not_a_member_error] (the default) raises [ERROR:TenancyDable::NotAMemberError] with a message naming the slug the request carried: an identifier, never the record.
- [VALUE:not_authorized] loads Pundit lazily and raises [ERROR:Pundit::NotAuthorizedError], so a host whose controllers already rescue that error needs no bespoke clause for non-members.
- A callable runs with [METHOD:instance_exec] in the controller's context, receives the resolved tenant as its only argument, and may redirect, render, `head :forbidden` or raise its own error; its outcome is the response.

[SPEC:spec/resolution/not_a_member_behavior_spec.rb] proves each mode and that a genuine member is admitted whichever mode is configured.

## Cable

[MODULE:TenancyDable::Channel] is the Action Cable parallel of the controller concern. It is opt-in: [FILE:lib/tenancy_dable.rb] does not require it, so Action Cable stays an optional dependency, and a host that runs channels requires [FILE:tenancy_dable/channel] and includes the module into an [CLASS:ActionCable::Channel::Base] subclass. The concern names no Action Cable constant, so requiring it before Action Cable is loaded is safe.

The gem does not own Cable authentication. The host's connection declares [METHOD:identified_by :current_user] and establishes it however it authenticates; the concern only reads [METHOD:current_user] off the channel and ships no auth code. The helper names a host channel inherits are [METHOD:current_tenant], [METHOD:current_membership], [METHOD:tenant_member?], [METHOD:reject_unless_member!], [METHOD:stream_for_tenant] and [METHOD:with_tenant_context]; [SPEC:spec/contract_spec.rb] locks them by responds-to.

- [METHOD:current_tenant] is found by slug from the subscription params with the non-bang [METHOD:find_by] and memoized for the subscription; it is nil for an absent or unknown slug. [CONFIG:on_tenant_not_found] is not consulted, because a channel rejects instead of raising.
- [METHOD:current_membership] is the connection user's [METHOD:membership_for] the tenant, memoized, nil when either side is nil. A nil tenant therefore yields no membership and the subscription is rejected, which is the secure outcome.
- [METHOD:reject_unless_member!] is the host's call in [METHOD:subscribed] and rejects the subscription for any non-member, a member of a different tenant included.
- [METHOD:stream_for_tenant] subscribes to the stream named `tenant:<id>` with an optional `:<suffix>`, keyed by id so a stream name is never shared between tenants. It reads the tenant's id, so call it only after membership is confirmed.
- [METHOD:with_tenant_context] runs a block with the tenant and the membership both set, for database reads in [METHOD:subscribed], where nothing wraps automatically.
- [METHOD:perform_action] is wrapped in [METHOD:with_tenant_context], so every client-invoked action runs tenant-scoped like a controller action and restores the prior context afterwards.

[RULE:perform_action stays public]. Action Cable dispatches actions through an explicit receiver, so a private override raises [ERROR:NoMethodError] and breaks all message dispatch; it is not part of the locked helper list for that reason. [SPEC:spec/channels/tenant_channel_spec.rb] proves subscribing and streaming for a member, rejection of a non-member, of a member of another tenant, of an unknown slug, of a numeric id in the slug slot and of an absent slug, that an action transmits the subscription tenant's id, that a read inside the action sees only that tenant's rows, and that no context survives the action. The harness channel is [FILE:spec/internal/app/channels/tenant_channel.rb].

## Residuals

[ABSENCE:Resolution is not installed on an API base class]. The railtie prepends onto [CLASS:ActionController::Base] only; a controller hierarchy rooted elsewhere prepends [MODULE:TenancyDable::Controller::Resolvable] itself.

[ABSENCE:Resolution publishes with plain assignments, not a block]. The tenant and membership live until the executor resets the current attributes at the end of the request; a code path that runs resolution outside a request lifecycle owns clearing them.
