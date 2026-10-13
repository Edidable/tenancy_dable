# Step 1: Intake - the spec, the scope, the plan

The run starts by understanding what is asked and fixing the scope before anyone writes code. The output is `tmp/<run>/PLAN.md`, the brief every later agent reads. `<run>` is the version without dots, e.g. `tmp/v060/` for `v0.6.0`.

## 1. Read the spec

- **A proposal file** (`IMPROVEMENT_PROPOSALS*.md` from a host, or any `.md` the user names): read it in full. It names items, measured evidence, a proposed API and the `DESIGN.md` sections it touches. It is gitignored and stays untracked: never commit it, never copy its host-specific vocabulary into the repo ([git.md](git.md) -> "Nothing private").
- **An issue URL**: read it with `gh issue view <url> --comments`.
- **The user's words**: restate them as items in the plan and confirm anything ambiguous.

Then read what the spec touches: `CLAUDE.md`, the domain hubs under `docs/domains/` for every area involved (and the spokes the items touch), `DESIGN.md` §1, §11 and the most recent delta section, and the code under `lib/`. The domain index is the `docs/domains/` directory; `.claude/rules/<name>.md` auto-loads when you open that domain's code.

## 2. Baseline

From the main checkout, before branching, prove the starting point is green:

```
git status --short          # clean apart from untracked spec files
bundle exec rspec           # record the example count
bundle update standard --conservative   # CI resolves the newest standard; no rspec running meanwhile
bundle exec standardrb
```

A red baseline is not this run's to fix silently: report it and ask whether it joins the scope. Record the example count in the plan (it is process state, not a doc fact).

## 3. Branch

```
git switch master && git pull --ff-only origin master
git switch -c <descriptive-name>
```

A descriptive, lowercase, hyphenated name, no prefix ([git.md](git.md) -> "Branches"). Every commit of the run lands on this branch; `master` moves only at release.

## 4. PLAN.md

Write `tmp/<run>/PLAN.md` (gitignored). It carries:

- **Repo facts the agents need**: the checkout path, the branch, the spec path, the baseline numbers, the suite and lint commands.
- **Scope: one release.** A table, one row per spec item: the item, what ships, and its kind (bug, security, feature, ergonomics). A spec that suggests splitting into several releases is a suggestion: the default is one release with every item, unless the user split it. Name any item left out and why.
- **Decisions already taken**: where the spec offers options, the one this run takes (the spec's recommendation by default) and why; anything only the user can decide is asked now, before design.
- **Phases**: the table of [SKILL.md](SKILL.md) section 2 adapted to this run - who does each phase (lead or which pinned agent) and what it hands the next.
- **Rules every agent follows**: the no-AI-attribution rule word for word, nothing private, the repo's code style (frozen_string_literal, Standard, the comment density of the surrounding code, `DESIGN.md` §N references in comments), every gem error under `TenancyDable::Error`, error messages with ids only (no record payloads), owned files only, specs run only in the agent's own checkout, the report line.

The plan is short and decisive: a scope table and a roster, not an essay. The designer (step 2) turns it into the frozen contract.

## 5. Plan mode (`plan-mode`)

With `plan-mode`, call `EnterPlanMode` (load it with `ToolSearch`, `select:EnterPlanMode`) once the branch exists, write the plan into the plan file the mode names, and `ExitPlanMode` for approval. On approval, copy it to `tmp/<run>/PLAN.md`. Agents launched while plan mode is on can write only the file beside the plan ([orchestrate.md](orchestrate.md) -> "Plan mode").

## 6. Stop point `plan`

With destination `plan`, the run ends here: hand the user the plan's path, the scope table, the version and the open questions, and end the turn. Otherwise continue to [design.md](design.md).
