---
paths:
  - "docs/**"
  - ".claude/rules/**"
---
Docs describe the gem, and only the gem. A doc under `docs/` must read as true and complete to someone with zero knowledge of how the code came to be: no release-run or phase references ("phase 03", "W1", "the fix round", "§16 says it was decided"), no people (names, "the maintainer asked"), no conversation or session traces ("as discussed", "nesta sessão"), no timeline narration ("since 0.5.0", "as of 2026-10-10", "formerly", "now"). The test: if a sentence answers "what happened / who wanted it / when", it does not belong; if it answers "what the gem is / how it behaves / why this design, in system terms", it does. Rationale is welcome, stated impersonally and timelessly: "the guard raises instead of adding a validation error because a foreign tenant id is never user input in a correct host", never "we chose a raise after the red team found F9". History lives in git, `CHANGELOG.md` and the `DESIGN.md` deltas.

Docs also describe only THIS gem. A fact about the machine a session runs on (an asdf Ruby, a Homebrew path, a password manager), about the agent tooling driving a session (how a subagent loads, how CI is polled, how a worktree sandbox behaves), or about a library in general with no wrinkle specific to this gem is not project knowledge and does not enter `docs/`. The test: "would this sentence be true, word for word, in any other Rails gem?"; if yes, it is not a fact about this one. The exception is a general fact that bites HERE because of a decision of this gem (Active Record's `WhereClause#merge` dropping a predicate is general; that it is why the default scope alone cannot stop `a.widgets` from reading another tenant is this gem's), and then the entry names the decision. `docs/gotchas.md` admits only traps that cut across domains; a single-domain trap lives in its domain doc, and a resolved bug with nothing left to watch for is git history.

Docs carry no DERIVABLE fact. A number a command answers - a count of errors, settings, hooks, spec files or examples, a gem version from a lockfile, a measured duration - is the state of the inventory on one day, and a routine commit changes it with no decision behind it, so the doc names the SOURCE, not the answer: "every error descends from `TenancyDable::Error` (`spec/contract_spec.rb` locks the list)", "the supported Rails range is the gemspec's", "the CI matrix in `.github/workflows/ci.yml`". The number that stays is a CONTRACT: it defines behaviour and changing it takes a decision (a payload of exactly three keys, the 60-character limit the gem enforces somewhere), anchored and welded to a spec. Two shapes are fine: a count the same sentence enumerates (`:current`, `:other`, `:removed`, `:unpinned`: four states), and a version a sentence depends on (a workaround pinned to a bug fixed in a named Rails release, with its row in `docs/upstream.md`). `ruby .claude/scripts/documentation/doc_census.rb` finds the common shapes; a contract number it flags goes in `.claude/scripts/documentation/.doc-census-allow` under a reason.

Docs carry no TRACKER or RUN reference: no issue or PR number, no proposal item number ("proposal 3", "F7", "S2"), no "until X lands", no "tracked in". A doc states the current state; a gap is a gap, a residual is a residual. The plan to change that state lives in the proposal file or the release run, which point at the doc, never the reverse. `docs/upstream.md` is the one carve-out: an upstream issue link, a maintainer's handle and a release date are its rows' CONTENT.

**Never write:**

- **Run/phase/session references**: a phase, a workstream id, a finding id, "the fix round", "this release", "this PR", "nesta sessão".
- **Tracker references**: an issue or PR number, a proposal item number, "until X lands".
- **People**: a name, a role acting ("the maintainer decided"), an approval trace.
- **Timeline narration**: a date stamp, "since vX.Y.Z", "as of", "formerly", "now", "currently" meaning "as of today".
- **Conversation traces**: "as discussed", "per the review", "changed after feedback".
- **Derivable numbers**: an inventory count ("twelve errors", "nineteen settings", "seven hooks"), a lockfile version, a measurement ("692 examples", "~15 µs").

**Examples:**

BAD: "Since 0.5.0 the read guard refuses `invert_where`." GOOD: "The read guard refuses `invert_where`: it turns the default scope's `tenant_id = current` into a `NotEqual`, which is no literal pin."

BAD: "The gem has 12 error classes." GOOD: "Every gem error descends from `TenancyDable::Error`; `spec/contract_spec.rb` locks the list."

BAD: "W2 decided `ConfigurationError` for bad declarations." GOOD: "A bad declaration raises `ConfigurationError`: it is a class-load misconfiguration, like an invalid setting."

BAD: "The red team found that upsert by primary key moves rows (F7)." GOOD: "An upsert whose conflict target lacks `tenant_id` is refused: a primary-key conflict can reach another tenant's row and rewrite its tenant."

Scope: this applies to every file under `docs/**` and to the prose of `.claude/rules/**` (a rule is the copy an agent reads mid-edit, so it carries no name, no date and no run code either). It does NOT apply to the root release documents, which have their own conventions: `CHANGELOG.md` and `UPGRADING.md` narrate versions by design, `README.md` is the user manual, and `DESIGN.md` is the contract tier (per-release delta sections that freeze signatures and record decisions with their run context; a delta is never rewritten after its release, only amended before it). `.claude/skills/**` are process instructions ("the release branch", "the red team") and are not held to the narration ban, but a skill still carries no person's name and no date. `docs/upstream.md` is the only carve-out inside `docs/`. `.claude/hooks/check_docs.rb` enforces the common patterns on every `docs/` and `.claude/rules/` edit; its pattern list is not exhaustive, so a phrasing it does not recognize is still banned by this rule.

Format: every file under `docs/` is written in Narrative Anchors (`[LABEL:value]` inside complete sentences); `.claude/skills/remember/narrative-anchors.md` is the format, and `/remember` is the way facts get in.
