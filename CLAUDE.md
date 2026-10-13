# tenancy_dable

`tenancy_dable` is the multi-tenancy layer of the edidable Rails SaaS skeletons, shipped as one versioned gem: a self-contained row-scoping engine (default scope, read guard, write guards, declared tenancy with an audit, fiber-safe context), the multi-workspace identity model (User ↔ Membership ↔ Tenant with roles), slug-based tenant resolution with membership enforcement, and a Pundit authorization context. Host apps consume it as a `git` dependency pinned by tag. It supports the Ruby and Rails lines in `tenancy_dable.gemspec` and the CI matrix in `.github/workflows/ci.yml`.

**This repository is PUBLIC.** Nothing private enters a tracked file, a commit or a tag message: never name a consumer app, its domain or its people. Say "a host" or "a production consumer". Proposal files a consumer hands over (`IMPROVEMENT_PROPOSALS*.md` at the root) are inputs to a release run: they are gitignored and never committed.

## Where knowledge lives - four tiers

| Tier | Files | What it is |
|---|---|---|
| User manual | `README.md` | how a host installs and uses the gem |
| Host upgrades | `UPGRADING.md`, `CHANGELOG.md` | what changed per version, the versioning policy, the behaviour differences a host must handle |
| Contract | `DESIGN.md` | the frozen per-symbol contract: §1-§12 the base, then one delta section per release (`## <n>. vX.Y.Z delta`) that amends what came before; a delta records decisions with their run context and is never rewritten after its release |
| Knowledge | `docs/` | the gem as it is, timeless, in Narrative Anchors: `docs/domains/<name>.md` hubs (and spokes), plus `architecture.md`, `decisions.md`, `gotchas.md`, `patterns.md`, `stack.md`, `upstream.md`; `docs/README.md` explains the system |

`DESIGN.md` says what a release FROZE; `docs/` says what the gem IS. When they disagree on current behaviour, the code decides, then `docs/` is fixed with `/remember sync`.

## Domain doc protocol - read before you work or answer

Mandatory context-gathering, without being asked:

1. When a task or the conversation is about a domain - its behaviour, conventions or rationale - **read that domain's hub `docs/domains/<name>.md` first**, before planning, answering or editing, even with no file open.
2. **Then follow the hub's `## Spokes` map** (when it has one) and open the spoke the work touches. The hub is the map; the spoke is the source of truth.
3. The index of domains is the `docs/domains/` directory itself. Each domain has a terse rule `.claude/rules/<name>.md` with the same name, whose `paths:` frontmatter auto-loads it when its code is edited; the hub is not auto-loaded, you open it per step 1. Open only the docs for the domain in front of you.

The security core is `scoping` (default scope, read guard, write guards) and `context` (the facade, fiber safety, the audited bypass): any change there reads both hubs and `docs/architecture.md`'s invariants first.

Scope: substantive domain work and any question of convention or rationale, not a typo fix.

## Code quality (required)

After any code change:

- `bundle exec rspec` - the whole suite is fast; run it on more than one seed before trusting a change to a guard (`--seed <n>`). **Never two rspec processes in one checkout**: the Combustion harness recreates one file-based SQLite database per checkout at boot, so a second run clobbers the first. Parallel work runs in separate worktrees (`.claude/skills/workflow/orchestrate.md`).
- `bundle exec standardrb` - Standard lint. The lockfile is gitignored, so CI resolves the newest `standard` the gemspec allows; run `bundle update standard --conservative` before trusting a clean local lint.
- `spec/contract_spec.rb` locks the public surface (errors, settings, signatures, hook visibility, constants): a change to the surface updates it in the same commit, together with `DESIGN.md`'s current delta and the README tables.
- Before a release, the other Rails lines locally with `.claude/skills/workflow/scripts/rails-matrix` (the CI matrix is the final word).

Conventions the code already follows (details in `docs/patterns.md`): every gem error descends from `TenancyDable::Error`; error messages and events carry identifiers only (model names, tenant ids, the tenant slug a request named), never a record or its attributes; framework classes are extended by `prepend` from the railtie; hooks forward with `(...)`; value objects are `Data.define`; settings are validated in `Configuration#validate!`; a code comment that explains a guard cites the `DESIGN.md` section that froze it.

## Git conventions

- **No AI attribution anywhere**: no `Co-Authored-By` trailer, no "Generated with", no session URL, no mention of Claude or any AI in commits, tag messages, branch names, code, comments or docs. Pass this rule word for word to every agent that writes a commit.
- Branch names are lowercase, dash-separated, descriptive, with no `<user>/` or `feature/` prefix. Commit titles follow `git log --format=%s` on `master`: imperative, specific, no ticket prefix.
- `master` is the default branch. Never force-push it; a red `master` is fixed forward.
- Releases follow `docs/domains/release.md` (the facts) and `/workflow` (the procedure). A push to `master` or a tag push is an outward act on a public repository: it happens only when the user asks for the release.

## Skills

- `/workflow` - the release lifecycle from a spec (a proposal file, an issue, a request) to a tagged version: intake, the `DESIGN.md` contract delta, foundation and parallel workstreams, adversarial verification and fix rounds, docs, release. Stop points `plan`, `design`, `impl`, `rc` (default), `release`. Multi-agent policy: `.claude/skills/workflow/orchestrate.md`.
- `/remember` - keeps `docs/` and the paired rules true: `learn` persists a durable fact from the conversation; `sync` reconciles `docs/` with the code after a release or a refactor, starting from the scans in `.claude/scripts/documentation/`.

## Writing docs

`.claude/rules/docs.md` is binding for `docs/**` and `.claude/rules/**`: the gem as it is, no run or phase ids, no people, no dates, no "since vX", no derivable counts, Narrative Anchors format. `.claude/hooks/check_docs.rb` flags the common shapes after every edit, and the edit is fixed before moving on.
