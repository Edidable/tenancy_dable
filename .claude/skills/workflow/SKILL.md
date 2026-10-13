---
name: workflow
description: "Full lifecycle of a tenancy_dable release: read the spec (a proposal .md, an issue, or the request), plan the scope, freeze the contract in a DESIGN.md delta, build it (foundation, then parallel workstreams in worktrees), verify it adversarially (red team, contract audit, fix rounds, final verify), update the docs, and cut the release (merge to master, Release commit, push master, CI green on its head, then the annotated tag and its push). No pull requests. Takes the target version vX.Y.Z (its dotless form is the run id), a stop point (plan, design, impl, rc, release) and the modes orchestrate, solo and plan. Load when the user asks to ship a version or resolve items of a proposal file - 'resolve os itens deste .md', 'faz o ciclo completo', 'orquestra com agentes', 'lança a release', 'ship 0.6.0', 'cut a release' - or to resume a release run in flight."
argument-hint: "[vX.Y.Z] [plan|design|impl|rc|release] [orchestrate|solo] [plan-mode] [<spec path or URL>] [what to do]"
---

# Workflow

The lifecycle of a tenancy_dable change, from the spec to the tag. One run ships one version: every item in scope lands in the same release unless the user splits it. The step files below are the procedure; the objective facts they rely on (how a release is shaped, how the harness behaves) live in `docs/domains/release.md` and `docs/domains/testing.md`, and the frozen public contract lives in `DESIGN.md`.

There are no pull requests in this version of the workflow: the work lands on a branch, is verified locally and adversarially, and reaches `master` through a local `git merge --no-ff` at release time. The CI gate is the pushed `master` head: the merge commit and the `Release X.Y.Z` commit are pushed together, the tag is created and pushed only after that head is green on every cell of the CI matrix, and `rake release` is never run (it would publish the gem to RubyGems and cut its own tag). The local gates in [gates.md](gates.md) run before that push, because nothing runs CI on the branch.

## 1. Settle the tokens, once

Arguments passed to this invocation: `$ARGUMENTS`

Nothing between the backticks means no tokens: every default applies. The placeholder itself, unreplaced, means this file was read rather than invoked: take the tokens from the user's message.

| Token | Becomes |
|---|---|
| `vX.Y.Z` | the target version; the run id `<run>` is it without dots (`v0.6.0` -> `v060`), used for `tmp/<run>/` and the `<run>/<name>` branches. With none, derive it from the spec and the versioning policy in `UPGRADING.md` (pre-1.0: a breaking or default-on change is a `0.MINOR` bump; additive only is still a minor; a pure fix is a patch) and confirm it with the user before filing anything |
| a path to a `.md`, an issue URL | the spec source; with neither, the spec is the user's words |
| `plan`, `design`, `impl`, `rc`, `release` | the destination (none given: `rc`) |
| `orchestrate`, `solo` | who does the work (none given: `orchestrate` when the spec has more than one item or touches more than one domain, `solo` otherwise) |
| `plan-mode` | enter plan mode after intake ([intake.md](intake.md) section 5) |
| any other text | the work, in the user's words |

Where each destination lands:

| Destination | Ends after | Hand the user |
|---|---|---|
| `plan` | [intake.md](intake.md) | `tmp/<run>/PLAN.md`: the scope table, the version, the phases and the roster |
| `design` | [design.md](design.md) | the committed `DESIGN.md` delta and what the probes proved |
| `impl` | [build.md](build.md) | the integrated branch, the gate results, what is still unverified |
| `rc` | [verify.md](verify.md) and the docs part of [release.md](release.md) | the release candidate: verified, documented, committed on the branch, nothing pushed; the accepted residuals and the deferred items |
| `release` | [release.md](release.md) | the tag, the `master` commit, CI green on both, the final report |

**`release` is an outward act on a public repository** (a push to `master` and a tag every host can pin). It runs only when this invocation's tokens or the user's own words ask for it: `release`, "lança a release", "publica", "e já solta a versão". A destination of `rc` never drifts into a push. At `rc`, report and ask whether to release; a later "pode lançar" resumes the run with destination `release`.

Plain words count like the token: "só planeja" -> `plan`; "até o contrato" -> `design`; "só implementa" -> `impl`; "deixa pronto pra lançar" -> `rc`; "até o fim e lança" -> `release`; "orquestra", "com agentes" -> `orchestrate`; "faz você mesmo", "sem agentes" -> `solo`.

**Ask, never guess**, when two destinations are given, when the version cannot be derived with confidence, or when a spec item depends on a decision only the user can make (a behaviour change the spec itself leaves open). A spec's own "recommended" option is a default you may take; say so in the plan.

## 2. Run the steps

| Step | File | What it produces |
|---|---|---|
| 1. Intake | [intake.md](intake.md) | branch, baseline, `tmp/<run>/PLAN.md` |
| 2. Design | [design.md](design.md) | the `DESIGN.md` delta, committed; probes proving the problem |
| 3. Build | [build.md](build.md) | foundation commit, workstream commits, integrated branch |
| 4. Verify | [verify.md](verify.md) | red team, contract audit, fix rounds, final verify |
| 5. Docs and release | [release.md](release.md) | release docs, `/remember sync`, then (destination `release`) the tag |

`solo` runs the same steps with the session doing the work; the design delta, the gates and the adversarial verification still apply (a `solo` run may verify with one `opus` agent covering both red team and contract audit). `orchestrate` follows [orchestrate.md](orchestrate.md) for every agent it creates.

Binding in every step: [git.md](git.md) (branch, commits, no AI attribution, nothing private) and [gates.md](gates.md) (the exact gate commands).

## Resuming

A run keeps its state outside the conversation: the plan and every agent report in `tmp/<run>/` (gitignored), and the work in git. Read the state back instead of re-deciding it:

| Signal | Means |
|---|---|
| `tmp/<run>/PLAN.md` exists | intake is done; its scope table and roster stand |
| a branch whose log shows `Freeze the vX.Y.Z contract in DESIGN.md §<n>` | design is done |
| `tmp/<run>/<agent>.md` reports | which agents finished, and what they found |
| `git worktree list` shows `../tenancy_dable-wt/*` on `<run>/*` branches | workstreams or fixers in flight or not yet integrated |
| `tmp/<run>/fix-round.md` | a verification round was decided; its buckets say what is fixed, docs-only or deferred |
| `CHANGELOG.md` `[Unreleased]` reads "To be released as `X.Y.Z`" | the release docs are written |
| `git tag -l vX.Y.Z` answers | the release is cut; check CI on the tag |

Continue from the first step whose output is missing. When a resumed run finds a report it has not read, read the file, not the notification.

## Bundled references

- [orchestrate.md](orchestrate.md) - the multi-agent policy: pins, worktrees, ownership, reports.
- [git.md](git.md) - branches, commits, merges, tags, the no-AI-attribution and nothing-private rules.
- [gates.md](gates.md) - every gate command, in the order the steps run them.
- [references/prompts/](references/prompts/) - fill-in prompt templates for every agent role.
- [scripts/rails-matrix](scripts/rails-matrix) - run the suite on another Rails line without touching the default lockfile.
