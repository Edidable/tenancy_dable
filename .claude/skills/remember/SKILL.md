---
name: remember
description: Persist what was learned into this gem's versioned docs/ knowledge base (and its paired .claude/rules/), or bring the docs back in line with the code after a release or refactor. Two modes. LEARN (default) saves a durable lesson, gotcha, decision, pattern or domain rule from the conversation; invoke for "/remember", "remember this", "write this down", "note in the docs", "add to the gotchas", "document the pattern we settled on", "persist this for next time", "save this to project knowledge", and in Portuguese "lembra disso", "anota nos docs", "documenta isso", "salva isso no conhecimento do projeto", and right after working out something non-obvious (a tricky bug's root cause, a rejected alternative, an always-do-it-this-way rule). SYNC (`/remember sync`, "atualiza os docs", "sincroniza os docs com o código", "sync the docs", and the docs step of /workflow) reconciles docs/ and the rules with the code and the latest DESIGN.md delta. Do NOT invoke for reading or querying existing docs, for one-off reminders ("remind me tomorrow"), for editing CLAUDE.md, README.md, DESIGN.md, UPGRADING.md, CHANGELOG.md or settings, or for personal memory.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Mirror project knowledge into docs/

This skill keeps the repository's own knowledge base, everything under `docs/` plus the paired `.claude/rules/<name>.md`, true to what the gem is. That knowledge lives in the repo, is versioned with the code and shows up in every diff, so another computer, a teammate and a fresh session all inherit it. It is not Claude Code's personal memory and it is not configuration.

Two modes share the same rules for what is worth keeping and how to write it:

- **learn** (default): one fact, or a handful, from the conversation goes into the right place. Steps L1 to L8.
- **sync** (`/remember sync`): the docs and rules are reconciled with the code after a release or refactor. Steps S0 to S7. The `/workflow` skill calls this in its docs step ([../workflow/release.md](../workflow/release.md) section 1), before the merge and the tag, so the knowledge base ships with the release.

If the invocation does not say `sync` (or an equivalent: "atualiza os docs", "sync the docs"), run learn.

## Companion references

- [narrative-anchors.md](narrative-anchors.md): the `[LABEL:value]` format every `docs/` file uses. Read it before writing prose.
- [context-loader.md](context-loader.md): the four tiers, the two layers, hub-and-spoke, and how a fact surfaces in a later session. Read it to know where a fact must live to be found.
- [templates/](templates/): fill-in skeletons for a hub, a spoke, a rule, a decision entry, a gotcha entry and an upstream row.

## What this skill may and may not write

| May write | Never writes |
|---|---|
| `docs/**` (cross-cutting files, `docs/domains/<name>.md` hubs, `docs/domains/<name>/*.md` spokes) | `CLAUDE.md`, `DESIGN.md`, `README.md`, `UPGRADING.md`, `CHANGELOG.md`: the release workflow owns them |
| `.claude/rules/<name>.md`: the rule paired with a hub (same filename, keep `paths:` frontmatter); a NEW rule for a NEW domain hub | `.claude/settings*.json`, `.claude/hooks/`, `.claude/scripts/`, other skills, personal memory (`~/.claude*`), `tmp/` run reports |

When the conversation produced something that belongs in a file it may not write (a README sentence, a `CHANGELOG.md` line, a `DESIGN.md` contract amendment, a hook change), name it in the final summary as a follow-up for the maintainer and do nothing else about it. `.claude/rules/docs.md` is itself a rule; edit it only when the user asks for a change to the writing policy.

## What lives where

| File | What it holds |
|---|---|
| `docs/architecture.md` | The layers of the gem and how they fit; the security invariants in system terms, each with its proving spec |
| `docs/decisions.md` | A real choice between alternatives, with the rejected option and why (`[CHOICE]`/`[REJECTED]`/`[RATIONALE]`) |
| `docs/gotchas.md` | Traps that cut ACROSS domains: "if you change X, also change Y". The last resort; a single-domain trap goes in its domain doc |
| `docs/patterns.md` | A convention that repeats across domains |
| `docs/stack.md` | Runtime and dev dependencies and why; names the gemspec and the CI matrix as the sources of ranges |
| `docs/upstream.md` | The ledger of dependency problems whose fix belongs upstream; a gotcha whose CAUSE is a library also gets a row |
| `docs/domains/<name>.md` | The hub of one domain: the narrative its paired rule points at |
| `docs/domains/<name>/<subtopic>.md` | A spoke: depth for a domain that outgrew one file |
| `.claude/rules/<name>.md` | The tight do/don't summary an agent reads mid-edit; auto-loads by `paths:` |

The domain roster is the `docs/domains/` directory itself; never copy it into a doc or this skill.

## Domain doc shapes: flat vs hub-and-spoke

- **Flat**: `docs/domains/<name>.md` is the whole story. The default, right for a cohesive domain, however long it gets.
- **Hub-and-spoke**: `docs/domains/<name>.md` is a lean hub (overview, the domain's principles, a `## Spokes` map with one line per spoke) and `docs/domains/<name>/<subtopic>.md` files hold the depth; each spoke opens, directly under its H1, with the back-link line `> Part of the [<name> domain](../<name>.md).`

[INVARIANT:the hub keeps its filename] because `.claude/rules/<name>.md` pairs with `docs/domains/<name>.md` by NAME. Never rename a hub to `index.md` or anything else; the pairing, `doc_parity.rb` and the CLAUDE.md domain-doc protocol all resolve the hub from that name. Nothing auto-loads a hub: the rule auto-loads by `paths:`, and the protocol sends the session to the hub and then to a spoke on demand.

# LEARN mode

## L1. Decide what is worth keeping (the admission test)

Read back over the conversation and pull out only durable, non-obvious facts about THIS gem: gotchas (a trap a future change can hit), decisions (a real choice with its rationale), patterns, domain rules (how a subsystem actually behaves). A fact passes only if it names something in the repo (a class, a setting, a spec, a file) AND a future session can run into it. Ask: "would this sentence be true, word for word, in any other Rails gem?" If yes it is general knowledge and stays out. The one exception is a general fact that bites HERE because of a decision of this gem; then the entry names the decision (Active Record's `WhereClause#merge` dropping a predicate is general; that it is why the default scope alone cannot stop `a.widgets` from reading another tenant is this gem's).

**Never save:**

- **Machine-local state**: an asdf Ruby, a Homebrew path, a password manager, a corrupted cache.
- **Agent and session tooling**: how a subagent loads, how CI is polled, how a worktree sandbox behaves, a grep gate from a plan. That is knowledge about the tools driving the work; name it as a follow-up for the operator's rules, never in `docs/`.
- **Generic Ruby, Rails, RSpec or Active Record knowledge with no wrinkle specific to this gem.**
- **Debugging diary and run narration**: how a finding was made, what was measured, which phase or workstream or finding id produced it, what a red team found. Keep the conclusion, drop the story. Release-run reports under `tmp/` explain WHY and which residuals were accepted: use them for rationale, never cite them.
- **Derivable facts**: a count of anything in the repo (errors, settings, hooks, specs, examples), a lockfile version, a measured duration. Name the source ("`spec/contract_spec.rb` locks the list", "the gemspec's range") and keep only CONTRACT numbers, anchored and welded to a spec. `.claude/rules/docs.md` carries the test; `ruby .claude/scripts/documentation/doc_census.rb` finds the common shapes.
- **Restatement**: anything the code, a rule, `CLAUDE.md` or an existing doc already states. Grep first (L3); a second copy is a second place to rot.
- **A resolved bug with nothing left to watch for**: that is git history. A gotcha stays only if a future change can reintroduce the trap, and then it says which change.

When code and a doc (or `DESIGN.md`) disagree, the code wins: the doc follows the code, and the disagreement goes in the summary.

## L2. Find the home: detect the shape and route

Run `Glob docs/domains/**/*.md` (the `**` catches spokes) and `Glob .claude/rules/*.md`, then route:

1. **A `docs/domains/<name>/` folder exists**: read the hub, route the fact to the spoke whose subtopic matches. If no spoke fits, create `docs/domains/<name>/<subtopic>.md` from [templates/domain-spoke.md](templates/domain-spoke.md) AND add its one-line entry to the hub's `## Spokes` map; a spoke the hub does not link will not surface.
2. **Only `docs/domains/<name>.md` exists (flat)**: edit the matching `##` section in place, then run the promotion check (L6).
3. **No domain home**: if the fact is cross-cutting, use the right `docs/*.md` file from the table. If it is a genuinely new domain (a new subsystem with its own code paths), create a flat hub from [templates/domain-hub.md](templates/domain-hub.md) AND its rule from [templates/domain-rule.md](templates/domain-rule.md) with `paths:` over the domain's code and specs; name them identically (`docs/domains/<name>.md`, `.claude/rules/<name>.md`). Do not pre-split a new doc into a folder.

Entry shape by kind: a decision is a `##` entry from [templates/decision-entry.md](templates/decision-entry.md) in `docs/decisions.md`; a gotcha is its own `### Gotcha: <short title>` heading with ONE paragraph carrying `[SYMPTOM:...]`, `[CAUSE:...]`, `[FIX:...]` and, when there is one, `[RULE:...]` ([templates/gotcha-entry.md](templates/gotcha-entry.md)), in its domain hub or spoke (grouped under `## Gotchas`) unless it cuts across domains; an upstream wrinkle is a row from [templates/upstream-row.md](templates/upstream-row.md) in `docs/upstream.md` (and the gotcha, if any, points at the row).

## L3. Read before you write (this is "mirror", not "append")

Open the target and read what is there. Update an anchor whose fact changed; add one only when the fact is new; delete one that is now wrong (a wrong fact is worse than a missing one). Refine a similar anchor in place instead of writing a second. Grep `docs/` and `.claude/rules/` for the fact's key term (the class, the setting, the error) before writing: when it already lives in a hub or a rule, the right edit is a pointer or nothing.

## L4. Write in Narrative Anchors

Embed each concrete fact as `[LABEL:value]` inside a complete sentence; strip the brackets and it must still read as English. The full format is in [narrative-anchors.md](narrative-anchors.md). Match the style of the target file. Write timelessly and impersonally, per `.claude/rules/docs.md`: no run, phase, workstream or finding id, no person, no date, no "since 0.5.0", "formerly", "as of", "this release", no tracker reference, no derivable number. Rationale is welcome in system terms. `DESIGN.md` may be cited as a pointer to the frozen contract ("the signatures are frozen in `DESIGN.md` §16.1"), sparingly. The `check_docs.rb` hook flags the common narration shapes right after every `docs/` and `.claude/rules/` edit, and `check_doc_refs.rb` flags a namespaced constant that does not exist, whether backticked or inside an anchor (`[CLASS:TenancyDable::Foo]`); both exit 2 so the line is fixed before moving on, and a phrasing the hooks miss is still banned.

## L5. Update the paired rule when the fact is a hard rule

A fact earns a bullet in `.claude/rules/<name>.md` only when an agent editing that domain's code needs it mid-edit: an invariant ("a relation built without a tenant is marked"), a trap ("never `include Scoped` by hand"), an "if you change X also change Y". Everything else stays in the hub or a spoke.

- One fact per line, terse, 8 to 25 lines for the whole rule; the last line points at `Narrative: docs/domains/<name>.md`.
- Keep the `paths:` frontmatter; widen it if the fact lives in code the globs miss.
- The rule never restates the hub's prose and carries no run, person, date or derivable number (same ban as docs).
- A rule is paired by NAME with its hub. Never create a rule without a hub or rename either.

## L6. Promotion check (flat to hub-and-spoke)

After editing a flat doc, decide whether it outgrew one file. **Promote** when it passes about 200 lines, or carries three or more `##` sections that are independent subsystems with their own growth curve, or the fact just added is a distinct sub-concern that would be the third such section. **Do not promote** a doc that is long but cohesive; depth is healthy, breadth triggers the split. On a borderline call, save the fact, leave the structure, and recommend the promotion in the summary.

Procedure: create `docs/domains/<name>/`; move each heterogeneous section verbatim into its own spoke (keep every anchor, add the `> Part of the [<name> domain](../<name>.md).` line under its H1); rewrite `docs/domains/<name>.md` down to a hub (2 to 4 sentence overview, the principles common to all spokes, a `## Spokes` map); keep the rule's name and extend its `paths:` if the spokes cover new code; fix references.

## L7. Make the edits and verify

Use `Edit` for surgical changes; `Write` for a new spoke, hub or rule (in bounded chunks for a long file). Then run, from the repo root, with plain `ruby`:

```bash
ruby .claude/scripts/documentation/check_doc_refs.rb --all
ruby .claude/scripts/documentation/doc_census.rb
ruby .claude/scripts/documentation/doc_parity.rb
```

Fix what your edit introduced (a stale constant, a derivable number, a hub without its rule or an unlinked spoke). Do not "fix" findings in files you did not touch; report them.

## L8. Summarize

Report what was added, updated or removed and in which files; then, one line each, what you deliberately did NOT save and why (machine-local, tooling, generic, derivable, restatement, resolved, run narration). Call out explicitly any new spoke, any new hub plus rule, any promotion done or recommended but not forced, and every follow-up for a file this skill may not write (`CLAUDE.md`, `README.md`, `CHANGELOG.md`, `DESIGN.md`).

# SYNC mode

Goal: after a release or refactor, `docs/` and the rules describe the code as it is now, with the latest `DESIGN.md` delta fully accounted for. Truth order: `lib/**`, then `spec/**`, then the `DESIGN.md` delta, then the other root docs. The code wins every disagreement.

## S0. Deterministic scans (run first, always)

```bash
ruby .claude/scripts/documentation/check_doc_refs.rb --all   # docs name constants that no longer exist
ruby .claude/scripts/documentation/code_index.rb --uncovered # lib/ constants no doc or rule names
ruby .claude/scripts/documentation/doc_census.rb             # derivable numbers in the docs
ruby .claude/scripts/documentation/doc_parity.rb             # rule <-> hub pairing, paths, linked spokes
```

Their output is the first worklist. A stale reference is fixed in the doc (or the code), or listed in `.doc-refs-allow` with a grouped reason when intentional. An uncovered constant is documented in its hub or consciously skipped. A census hit is rewritten as the source that answers it (never re-measured); a genuine contract number goes in `.doc-census-allow` under a reason. A parity failure is fixed by NAME: create the hub or the rule with the exact matching name, add the missing `paths:`, or link the spoke from the hub's `## Spokes` map.

## S1. Read the latest delta

Find it: `grep -n '^## [0-9]*\. v[0-9.]* delta' DESIGN.md`, take the highest section number. Read its contract-impact summary, its contract-spec delta and every subsection it freezes. That section is the checklist: each symbol, setting, error, rule and accepted residual it freezes must be described in the right hub or spoke.

## S2. Reconcile the delta against `docs/domains/`

For each frozen item, in order of the delta's subsections:

1. Grep `docs/` and `.claude/rules/` for its key term. Missing, stale or contradictory means work.
2. Read the code (and the spec that proves it) before writing; if the delta and the code disagree, write what the code does and list the disagreement in the report.
3. Write it in the right hub or spoke in present tense (L4). A delta is run context: strip the run narration (no "decided", no finding ids, no "new in this release", no "was X, now Y"). The rationale stays, in system terms. A pointer to the frozen contract ("frozen in `DESIGN.md` §16.1") is fine.
4. Residuals the delta accepts are documented as residuals (`[RESIDUAL:...]`), stated as what the gem does not guarantee, not as a to-do.
5. A guardrail sentence that names a removed or forbidden thing ("there is no X", "X is not kept as a fallback") is the most valuable kind; keep it and list the name in `.doc-refs-allow` if it is a constant that no longer exists.

## S3. Reconcile the rules

For each paired rule: every `paths:` glob still matches real files and covers the code the hub describes (new `lib/` files and new specs are in some rule's `paths:`); the bullets still match the hub and the code; a new invariant from the delta has its bullet; a deleted behaviour has none left. Code with no rule covering it and a subsystem of its own gets a new hub plus rule (L2, case 3). Keep each rule within its size budget by moving prose to the hub.

## S4. Cross-cutting files

Check `docs/architecture.md` (layers and invariants still match; each invariant names its proving spec), `docs/decisions.md` (a decision the delta records and no entry carries gets one; a superseded entry is rewritten, not stacked), `docs/stack.md` (against the gemspec and the CI matrix; name the source, not the version), `docs/upstream.md` (a workaround the delta added or removed moves its row), `docs/patterns.md`, `docs/gotchas.md` (cross-domain traps only; single-domain ones move to their domain), and the domain list in `docs/README.md` (it points at the `docs/domains/` directory, never lists it).

## S5. Re-run the scans green

Run the four commands of S0 again. Every stale reference fixed or allow-listed, every coverage gap documented or consciously skipped, every derivable number rewritten or allow-listed as a contract, every rule paired with its hub.

## S6. Do not edit the release documents

Findings inside `CLAUDE.md`, `README.md`, `DESIGN.md`, `UPGRADING.md` or `CHANGELOG.md` (a stale reference, a derivable count) are reported for the maintainer, never edited, and a scan exit of 1 whose only hits are in those files is not work left undone.

## S7. Report

Summarize: files changed (grouped by hub), delta items reconciled, delta-versus-code disagreements, items consciously skipped and why, scan results (before and after), and follow-ups for files this skill may not write. Keep it short; the diff carries the detail.

## Guidelines (both modes)

- **Mirror, don't append**: update and delete as much as you add.
- **Don't bloat**: a hub is an overview and principles, a spoke is depth, a rule is a dozen lines.
- **Never re-measure a stale number**: a count or version that drifted proves the doc should not have carried it.
- **A grep is the start of a sweep, never the sweep**: real drift ("the guard allows X" after X became refused) usually contains no removed name; it is found by reading the hubs against the code.
- **Delete stale info**: wrong knowledge is worse than none.
