# Context loader: how `docs/` knowledge reaches a later session

This explains how the repo's knowledge is stored and surfaced, so a fact `/remember` writes lands where a future session will actually read it. Loading everything floods the context with noise; loading nothing misses what matters. The structure below makes loading selective.

## The four tiers

The tiers are the ones `CLAUDE.md` names:

| Tier | Files | Convention | Written by |
|---|---|---|---|
| **User manual** | `README.md` | How a host installs and uses the gem; the host-facing surface | The release workflow, never `/remember` |
| **Host upgrades** | `UPGRADING.md`, `CHANGELOG.md` | They narrate versions by design: what changed per version, the versioning policy, the behaviour differences a host must handle | The release workflow, never `/remember` |
| **Contract** | `DESIGN.md` | The frozen per-symbol contract: numbered sections, per-release delta sections (`## <n>. vX.Y.Z delta ...`) that freeze signatures and record decisions with their run context. A delta is amended before its release, never rewritten after | The release workflow, never `/remember` |
| **Knowledge** | `docs/` and the paired `.claude/rules/` | Present-tense description of the gem as it is, in Narrative Anchors, with no run narration (`.claude/rules/docs.md`) | `/remember` (learn and sync) |

The tiers answer different questions. `README.md`: how do I use the gem. `UPGRADING.md` and `CHANGELOG.md`: what changed and what must I do when I bump. `DESIGN.md`: what exactly was promised, and what did that release decide. `docs/`: how does the gem behave and why this design, in system terms, for someone who has never seen how it was built. Where tiers overlap, the knowledge tier points at the contract tier ("frozen in `DESIGN.md` §16.1") instead of copying it. `/remember sync` is the bridge: it reads the latest delta and restates what it froze as present-tense knowledge in `docs/domains/`.

## The two-layer model (inside the knowledge tier)

Knowledge is split across two trees that work as a pair:

| Layer | Lives in | Role |
|---|---|---|
| **Narrative** | `docs/domains/<name>.md` (+ `docs/domains/<name>/` spokes) and the cross-cutting `docs/*.md` files | The full prose, in Narrative Anchors. Versioned with the code, reviewed with it, read by humans and by Claude |
| **Rule** | `.claude/rules/<name>.md` | A short summary whose YAML `paths:` frontmatter scopes when it auto-loads: the tightest do/don't lines |

[RULE:rules point at their hub, never the reverse] because a rule pairs with its narrative hub by the SAME FILENAME and ends with `Narrative: docs/domains/<name>.md`; the narrative never points back at `.claude/`. In this repo `/remember` may write both layers: the narrative always, and the rule when a fact is a hard rule or when a new domain hub needs its rule. The one convention rule without a hub is `docs` (the writing policy), listed in `doc_parity.rb`'s `PROCESS_RULES`.

## How a domain doc surfaces

Three paths lead a session to a fact:

1. **Rule auto-load by `paths:`.** Claude Code loads `.claude/rules/<name>.md` when an edited file matches the globs in its frontmatter. The globs cover the domain's code and its specs, so editing `lib/tenancy_dable/relation_extension.rb` surfaces the `scoping` rule. The rule is the tight summary read mid-edit, and its last line names the hub.
2. **The `CLAUDE.md` domain-doc protocol.** It tells every session to read a domain's hub, and the relevant spoke, whenever the work or the conversation is about that domain or needs depth, even with no file open. The protocol names the `docs/domains/` directory as the index: a filename match is how a hub is found.
3. **Hub links.** A hub's `## Spokes` map is the only route to a spoke.

The practical consequence for `/remember`: **a fact surfaces only if it lives in, or is linked from, the hub.** A spoke the hub does not link is invisible until someone opens it by accident; `doc_parity.rb` fails on that. A new domain hub with no rule is found by name through the index but never auto-loads on edits, so a new hub is always created together with its rule.

## Hub-and-spoke: keep the auto-loaded part lean

A domain doc has one of two shapes:

- **Flat**: `docs/domains/<name>.md` is the whole story. The default for a cohesive domain.
- **Hub-and-spoke**: `docs/domains/<name>.md` is a lean hub (overview, the domain's principles, a `## Spokes` map with one line per spoke) and `docs/domains/<name>/<subtopic>.md` files hold the depth, each opening, directly under its H1, with the back-link line `> Part of the [<name> domain](../<name>.md).`

The hub keeps its filename so the rule-to-hub pairing never changes. A session reads the small hub first and a spoke on demand, instead of dragging an ever-growing monolith into every unrelated edit. [PRINCIPLE:load the map, lazy-load the detail]: the hub is a table of contents with principles, the spokes are the chapters, and the rule is the cheat sheet.

## Cross-cutting homes (not domain-specific)

| File | When a fact belongs here |
|---|---|
| `docs/architecture.md` | How the layers fit together; the security invariants in system terms, each with its proving spec |
| `docs/decisions.md` | A real choice between alternatives, with the rejected option and why |
| `docs/gotchas.md` | A trap that cuts across domains: "if you change X, also change Y". Keep small; it is read often |
| `docs/patterns.md` | A reusable convention that spans domains |
| `docs/stack.md` | Dependencies and why; the gemspec and the CI matrix are the sources of versions |
| `docs/upstream.md` | A dependency problem whose fix belongs upstream, with the local workaround and next step |

## Finding the right home before writing

1. `Glob docs/domains/**/*.md` and `Glob .claude/rules/*.md` (the `**` catches spokes inside folders).
2. If a domain folder exists, read its hub first, then the spoke closest to the fact.
3. If only a flat file exists, read it.
4. If nothing matches, the fact is either cross-cutting (a `docs/*.md` file above) or a brand-new domain (a flat hub plus its rule, same name, `paths:` over the domain's code).

## When to read manually vs. rely on auto-load

Rely on the auto-loaded rule for routine edits inside one domain. Read the docs yourself when the task spans several domains, when the user asks why something is done a certain way (`docs/decisions.md`), when you are about to restructure, or when syncing after a release and you need the hub, its spokes and the `DESIGN.md` delta in view together.
