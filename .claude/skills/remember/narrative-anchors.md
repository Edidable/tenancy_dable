# Narrative Anchors: the writing format for `docs/`

The canonical format for every file under `docs/` in this repo, and for the prose of the paired `.claude/rules/` files. Match it; do not invent a competing style.

## Core principle

Embed each structured fact inside natural prose using a bracket anchor: `[LABEL:value]`.

The surrounding sentence carries the relationships, causality and nuance that raw key-value data cannot. The anchor makes the fact grep-able; the prose makes it understandable. Strip every bracket and the paragraph must still read as normal English.

## Why it works

- **Natural-language alignment**: Claude reads prose natively, so there is no translation step between reading and understanding.
- **Redundant encoding**: `[ERROR:CrossTenantReadError]` states the value explicitly, and "the guard raises" states it through context. If one channel degrades, the other preserves the fact.
- **Relational context**: plain key-value pairs give facts but not significance. Prose tells you how facts relate, what they imply and when they matter.
- **Greppable**: `grep -rn 'ERROR:CrossTenantReadError' docs/` finds every place the fact is stated, which is how `/remember` avoids a second copy.

## Rules

### Rule 1: labels are UPPERCASE

Write `[CONCERN:Scoped]`, never `[concern:Scoped]`.

### Rule 2: labels are semantic, not positional

Use `[METHOD:belongs_to_tenant]`, never `[ITEM_3:belongs_to_tenant]`. The labels in use across the docs: `[METHOD:...]`, `[CLASS:...]`, `[MODULE:...]`, `[CONST:...]`, `[FILE:...]`, `[ERROR:...]`, `[CONFIG:...]`, `[SPEC:...]`, `[REF:...]` (a pointer to another doc), `[SPOKE:...]`, `[RULE:...]`, `[DECISION:...]`, `[ABSENCE:...]`, `[RESIDUAL:...]`, `[RAKE:...]`, `[MARKER:...]`, and `[SYMPTOM:...]`, `[CAUSE:...]`, `[FIX:...]` inside a gotcha. Reuse an existing label before coining one; grep `docs/` for it.

A constant may be named in full (`[CLASS:TenancyDable::NoTenantError]`). `check_doc_refs.rb` reads the namespaced constant an anchor value starts with (`[METHOD:TenancyDable::Audit.run]` yields `TenancyDable::Audit`), exactly like a backticked name, so an anchor naming a constant that no longer exists is flagged after the edit.

### Rule 3: every anchor lives inside a complete sentence

Never leave an orphaned anchor. Instead of:

```
[FILE:lib/tenancy_dable/relation_extension.rb]
```

write:

```
The read guard is a prepend on `ActiveRecord::Relation` defined in
[FILE:lib/tenancy_dable/relation_extension.rb], installed once by the railtie.
```

### Rule 4: prose encodes relationships, anchors encode facts

The fact is `[ERROR:CrossTenantReadError]`. The relationship is the sentence:

```
A scoped relation pinned to a tenant other than the active one is refused with
[ERROR:TenancyDable::CrossTenantReadError] at load time, because a default scope alone
cannot stop `a.widgets` from reading another tenant once `merge` drops its predicate.
```

### Rule 5: no temporal markers, no process

Docs describe the gem as it is. A date, "since 0.5.0", "formerly", "as of", "now", a run or phase reference, a workstream or finding id, a session or a person is process narration, banned by `.claude/rules/docs.md`; `.claude/hooks/check_docs.rb` flags the common shapes right after the edit (exit 2), and the edit is fixed before moving on. Instead of:

```
In [TIME:0.5.0] the red team found the read gap (F7), so [EVENT:the read guard was added].
```

write the current state and its rationale, with no date and no id:

```
Reads are guarded: a scoped relation pinned to another tenant raises, because the default
scope's predicate can be dropped by `merge`, `unscope` or `unscoped`. History lives in git,
the CHANGELOG and the DESIGN.md deltas.
```

### Rule 6: one fact per anchor, one anchor per fact

Do not pack values: `[SETTINGS:require_tenant, guard_reads, isolation_check]`. Split them:

```
Three settings decide how strict the engine is: [CONFIG:require_tenant] makes a scoped query
with no active tenant raise (it defaults to fail-open), [CONFIG:guard_reads] turns the read
guard on, and [CONFIG:isolation_check] decides what a shared-state isolation level does.
```

### Rule 7: anchors carry contract, never census

`[PAYLOAD_KEYS:reason, tenant_id, call_site]` (the bypass event carries exactly those three keys, welded by a spec) defines behaviour: changing one takes a decision, so the anchor is the place to find it. `[ERRORS:12]`, `[SETTINGS:19]`, `[VERSION:rails 8.1.3]`, `[DURATION:~15 µs]` are the answer a command gives on one day and rot on the next commit; a stale anchor discredits the sentence around it. Name the source instead:

```
Every gem error descends from [CLASS:TenancyDable::Error]; [SPEC:spec/contract_spec.rb] locks
the list, so adding or removing one is a deliberate contract change.
```

### Rule 8: negative knowledge is explicit

If something is unknown or deliberately absent, say so in plain words:

```
`Membership` has [ABSENCE:no default scope on tenant_id] on purpose: it is queried to
discover a user's tenants before any tenant is current, so scoping it would deadlock the
fail-closed engine.
```

A guardrail sentence of this kind ("there is no X", "X is not kept as a fallback") is among the most valuable lines in a doc; keep it and name the thing.

### Rule 9: residuals are stated as what is not guaranteed

A known gap is a `[RESIDUAL:...]` anchor in a sentence that says what the gem does not promise, never a to-do and never a tracker reference:

```
A thread started without `TenancyDable.carry` or a restored snapshot begins with no tenant,
so with `require_tenant` off its scoped queries are fail-open: that lost context is a
[RESIDUAL:unmarked lost context], and the gem does not promise to detect it.
```

## Example: converting raw notes to Narrative Anchors

**Raw:**

```
- belongs_to_tenant adds a default scope on the current tenant
- no current tenant and require_tenant on => raises NoTenantError
- model declared twice => ConfigurationError
- TenancyDable.audit lists undeclared models
```

**Narrative Anchors:**

```
A model opts into scoping with [METHOD:belongs_to_tenant], which installs the fail-closed
default scope on the active tenant. With [CONFIG:require_tenant] on, a query or even a
`Model.new` with no active tenant raises [ERROR:TenancyDable::NoTenantError]; with it off
(the default) the relation is marked [MARKER:BuiltWithoutTenant] so loading it later inside a
tenant is refused instead of reading every tenant. A model that declares its tenancy twice
raises [ERROR:TenancyDable::ConfigurationError] before anything is installed, and
[METHOD:TenancyDable.audit] (the [RAKE:tenancy_dable:audit] task) reports every model that
declares nothing.
```

## Gotcha and decision entries

A **gotcha** is its own `### Gotcha: <short title>` heading with ONE paragraph under it, carrying `[SYMPTOM:...]`, `[CAUSE:...]`, `[FIX:...]` and, when there is one, `[RULE:...]`, each in its own sentence. It sits in its domain's hub or spoke (under a `## Gotchas` heading when there are several), never as an inline `[GOTCHA:...]` inside a longer section. It carries the conclusion, never the diary: no measurements, no "verified with", no story of how it was found. See [templates/gotcha-entry.md](templates/gotcha-entry.md).

```
### Gotcha: a uniqueness check reads before the write guard does

[SYMPTOM:a foreign-tenant create raises CrossTenantReadError instead of CrossTenantWriteError].
[CAUSE:a validator runs its uniqueness query before the refusal]. [FIX:the refusal callbacks
are installed with `prepend: true` so they run before every validator]. [RULE:keep the refusal
callbacks prepended when touching `belongs_to_tenant`].
```

A **decision** entry carries `[CHOICE:...]`, `[REJECTED:...]`, `[RATIONALE:...]` (and optionally `[TRADEOFF:...]`, `[TRIGGER:...]`): see [templates/decision-entry.md](templates/decision-entry.md).

## Quality checklist

Before finalizing an edit:

- [ ] Every concrete fact has a `[LABEL:value]` anchor.
- [ ] Every anchor sits inside a complete sentence.
- [ ] Labels are UPPERCASE and semantically meaningful, reused from the existing docs where one fits.
- [ ] No date, run, phase, workstream or finding id, tracker reference, session or person anywhere; the paragraph describes the gem as it is.
- [ ] No derivable number (an inventory count, a version from a lockfile, a measurement); every number left is a contract, or the sentence enumerates what it counts.
- [ ] Relationships are in prose, not crammed into anchors.
- [ ] Unknown or absent information is stated explicitly.
- [ ] A gotcha is its own `### Gotcha: <short title>` heading with one paragraph; a spoke opens with `> Part of the [<name> domain](../<name>.md).` directly under its H1.
- [ ] The paragraph still reads as normal English with every bracket stripped.
- [ ] No duplicate of a fact already in this file, another `docs/` file or the paired rule.
