# Knowledge System

This directory is the [TIER:knowledge] tier of `tenancy_dable`: the narrative companion to the code, written so that someone who has never seen the repository can learn how the gem behaves, why it is built that way, and which traps sit between two domains. It describes the gem as it is. It records no history, no people and no plan; those live in git, `CHANGELOG.md` and the `DESIGN.md` deltas.

## The Four Tiers

The repository keeps four kinds of documentation, and each fact has exactly one home.

1. The user manual is [FILE:README.md]: how a host installs and uses the gem.
2. The host-upgrade documents are [FILE:UPGRADING.md] and [FILE:CHANGELOG.md]: what changed per version, the versioning policy and the behaviour differences a host must handle. They narrate versions by design.
3. [FILE:DESIGN.md] is the [TIER:contract] tier: the frozen per-symbol design, with one section per delta that freezes signatures and records the decisions with their run context. Where an earlier section disagrees with the latest delta, the latest delta wins, and where `DESIGN.md` disagrees with `lib/`, the code wins. A delta is amended only before its release and never rewritten afterwards.
4. `docs/` (this directory) is the [TIER:knowledge] tier and answers "how does the gem behave and why?", without ever telling a story about how it got there. Every file here follows [FORMAT:Narrative Anchors].

The versions and dates of a release live in the second and third tiers (and, inside `docs/`, only in the rows of [FILE:docs/upstream.md]); the knowledge tier states the gem as it is.

The test for which tier a sentence belongs to is the one in [FILE:.claude/rules/docs.md]: a sentence that answers "what happened, who wanted it, when" does not belong in `docs/`; a sentence that answers "what the gem is, how it behaves, why this design in system terms" does.

## Narrative Anchors Format

Every concrete fact in `docs/` is a bracket anchor inside a complete sentence: the error a guard raises is written as [ERROR:TenancyDable::CrossTenantReadError], the file that holds the guard as [FILE:lib/tenancy_dable/relation_extension.rb], the setting that switches it off as [CONFIG:guard_reads]. Labels are UPPERCASE and semantic (`METHOD`, `FILE`, `ERROR`, `CONFIG`, `RULE`, `GOTCHA`, `SPEC`, `ABSENCE`, `RESIDUAL`), and stripping the brackets must leave ordinary English. The prose carries the relationships and the causality, and the anchor makes the fact greppable. [FILE:.claude/skills/remember/narrative-anchors.md] is the canonical statement of the format; match it rather than inventing a competing style.

Two constraints from the `docs` rule shape how facts are written:

- A doc names the SOURCE of a derivable fact, never the answer. The list of errors is locked by [SPEC:spec/contract_spec.rb], the supported Rails range is the gemspec's, the supported Ruby and Rails lines are the CI matrix in [FILE:.github/workflows/ci.yml]. A number stays only when it is a contract (the three keys of the bypass event payload) or when the same sentence enumerates what it counts.
- A doc carries no reference to the work that produced it and no tracker reference. A gap is stated as a gap and a residual as a residual.

## How the Rule and Domain Pair Works

Every domain lives in two files that share ONE name.

1. [FILE:.claude/rules/NAME.md] is the terse rule: YAML frontmatter with a `paths:` list of globs over the domain's code and specs, then short do/don't lines. It auto-loads when a matching file is being edited, and it is what an agent reads mid-edit.
2. [FILE:docs/domains/NAME.md] is the narrative hub: an overview, the domain's principles with their rationale, and its gotchas. A rule never repeats the hub's prose, and the hub never exists without its rule.

The name is the contract. A task is matched to a filename under `docs/domains/`, so a rule whose hub lives under another name is found by nobody. The one rule without a hub is the process rule [RULE:docs], which governs this directory itself rather than describing code.

A domain big enough to need depth is hub-and-spoke: the hub keeps the overview and a `## Spokes` map with one line per spoke, and each spoke under `docs/domains/NAME/` carries, directly under its H1, the back-link line `> Part of the [NAME domain](../NAME.md).`. Read the hub first, then only the spokes the work touches. The domains that use spokes are the ones whose hub carries a `## Spokes` section.

The domain roster is the `docs/domains/` directory: the files in it are the domains, and adding a domain means adding the hub and its same-named rule together.

## Adding New Knowledge

Use the `/remember` skill when something learned should persist. It decides which file the fact belongs in, writes it in Narrative Anchors, and reminds you to update the matching rule when the fact is a hard do/don't. By hand, the same steps apply:

1. Put a domain fact in the domain hub, or in the spoke if the hub has one for it. A trap that belongs to one domain is one paragraph under its own `### Gotcha: <short title>` heading in that domain's doc (hub, flat or spoke), shaped [SYMPTOM:...], [CAUSE:...], [FIX:...] and, when there is one, [RULE:...].
2. Put a fact that spans domains in one of the cross-cutting files below.
3. If the fact is a hard do/don't, add one line to the same-named rule under `.claude/rules/`.
4. Grep `docs/` for the key term first; a duplicate is a fact that will rot in one of its two homes.

The `docs` rule is checked after every edit under `docs/` and `.claude/rules/` by the hook [FILE:.claude/hooks/check_docs.rb], which flags a violation once the edit has landed (it does not prevent the edit) so the edit is fixed before moving on; its pattern list is not exhaustive, and a phrasing it misses is still banned. The census script [FILE:.claude/scripts/documentation/doc_census.rb] finds derivable numbers, and a contract number it flags is allowed with a reason in [FILE:.claude/scripts/documentation/.doc-census-allow].

## Cross-Cutting Knowledge

These files carry knowledge that spans domains rather than belonging to one:

- [FILE:docs/architecture.md] describes the layers, how they fit together, and the security invariants each with the spec that proves it.
- [FILE:docs/decisions.md] is the log of durable design decisions, each with the choice, every rejected alternative, and the rationale.
- [FILE:docs/gotchas.md] holds only the traps that cut across domains, plus a pointer list to the traps documented inside domains.
- [FILE:docs/patterns.md] holds the conventions every file in `lib/` follows.
- [FILE:docs/stack.md] names the runtime and development dependencies and why each is there.
- [FILE:docs/upstream.md] is the ledger of dependency problems whose fix belongs to the library, and the only file under `docs/` allowed to carry tracker links, handles and release dates.

## Domains

The domain hubs live in [DIR:docs/domains/]. Open the hub whose name matches the work, for example the read guard is in [FILE:docs/domains/scoping.md] and its spoke [FILE:docs/domains/scoping/read-guard.md], the `Current` facade and the audited bypass are in [FILE:docs/domains/context.md], and the test harness is in [FILE:docs/domains/testing.md]. The layer-to-domain map is in [FILE:docs/architecture.md].
