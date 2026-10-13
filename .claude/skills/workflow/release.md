# Step 5: Docs, then the release

Section 1 (the docs) belongs to every run that reaches `rc`. Sections 2-5 (the release itself) run only with destination `release` ([SKILL.md](SKILL.md) -> "`release` is an outward act"). The release's shape - what the `Release` commit touches, how tags look, how hosts consume a version - is described in `docs/domains/release.md`; this file is the procedure.

## 1. The docs

Three kinds of document change with a release, each with an owner:

- **Release docs** (one `sonnet` agent, [references/prompts/docs.md](references/prompts/docs.md); it owns `README.md`, `UPGRADING.md`, `CHANGELOG.md` only and never runs specs, so it may run beside the red team):
  - `CHANGELOG.md`: under `## [Unreleased]`, "To be released as `X.Y.Z`. See [UPGRADING.md](UPGRADING.md#<anchor>)." and the `### Security` / `### Added` / `### Changed` sections in the file's voice. No dated heading, no compare-link change, no version bump: the `Release` commit does those.
  - `UPGRADING.md`: a section for the version in the "behavior differences to expect" style, every host-visible refusal or behaviour change with its fix and its escape hatch, linked from the bumping section.
  - `README.md`: each new surface where it belongs, every example matching the real signatures, the residuals of every guard.
- **The contract** (one `sonnet` agent, or the lead): the `DESIGN.md` delta amended IN PLACE to match the code after the fix rounds (the release is not out, so the delta is still editable; after the tag it is frozen), plus the contract-spec locks the fixers listed. It starts after the fix round is integrated, and it runs specs in the main checkout only while no probe set or suite is running there ([verify.md](verify.md) section 1).
- **The knowledge base**: `/remember sync` over the release diff (`git diff master...HEAD`), so `docs/domains/` and the paired `.claude/rules/` describe the gem as it now is, and `/remember` for each durable lesson of the run (a gotcha, a decision with its rejected alternative). The release-run reports in `tmp/<run>/` are its input; nothing in `docs/` cites them.

Then the gate ([gates.md](gates.md) -> "Release-candidate gate") and the docs-vs-code check of the final verify ([verify.md](verify.md) section 4). Commit each kind separately (`Document vX.Y.Z: <summary>`, `Amend the vX.Y.Z contract to the verified code, and lock it`, `Sync the knowledge base with vX.Y.Z`).

With destination `rc`, stop here ([verify.md](verify.md) section 6).

## 2. Merge into master

No pull request is opened: the release branch is merged locally.

```
git switch master && git pull --ff-only origin master
git merge --no-ff <branch> -m "Merge branch '<branch>'"
```

A merge commit, so `master` keeps one commit per release branch and the branch's own commits stay reviewable one by one. If `master` moved since the branch started, rebase the branch onto it first (`git rebase master` on the branch, then the gate again) rather than resolving conflicts in the merge.

## 3. The Release commit

On `master`:

- `lib/tenancy_dable/version.rb`: `VERSION = "X.Y.Z"`.
- `CHANGELOG.md`: `## [Unreleased]` becomes `_Nothing yet._`, followed by `## [X.Y.Z] - <today>` and the "See UPGRADING" line; at the bottom, `[Unreleased]` compares from `vX.Y.Z...HEAD` and a new `[X.Y.Z]` line compares the previous tag to `vX.Y.Z`.
- grep `lib/` and `spec/` for the old version string: only `version.rb` changes; mentions of earlier versions in prose are history and stay.

Run the gate once more on `master` (the suite, `standardrb`, `gem build` with its contents check), then:

```
git add lib/tenancy_dable/version.rb CHANGELOG.md
git commit -m "Release X.Y.Z"
```

## 4. Push master, CI, then the tag

```
git push origin master
```

The CI gate is this pushed `master` head: the merge commit and the Release commit leave together, so the head is the first commit CI ever sees and the one it must pass. Watch every run CI starts for that commit from a background shell, writing to a file rather than piping (`gh run list --commit <sha>` for the ids, then `gh run watch <id> --exit-status` per run). The full matrix of `.github/workflows/ci.yml` must be green, lint included, on every cell, before the tag exists.

- **Red**: fix forward on `master` (a new commit, the gate, push), never tag a red commit, never force-push `master`. A flake gets one `gh run rerun <id> --failed`; a second failure is a real failure.
- **Green**: tag the exact commit CI passed, annotated, with a one-line summary in the shape of the previous tags (`git tag -n1 -l 'v*'`):

```
git tag -a vX.Y.Z -m "vX.Y.Z: <one line: what the release adds>"
git push origin vX.Y.Z
```

The tag push runs CI again; watch it the same way. The release is done when the tag's run is green. There is no RubyGems publish and no GitHub Release object: hosts pin the tag (`docs/domains/release.md`). Never run `rake release`: `Rakefile` loads `bundler/gem_tasks`, so it would push the gem to RubyGems and create its own tag.

## 5. Clean up and report

- `git worktree list`: remove every `../tenancy_dable-wt/*` worktree of the run (`git worktree remove`, `--force` only for a detached verifier worktree with nothing to keep), `git worktree prune`.
- Delete the `<run>/*` branches (`git branch -D`; they were cherry-picked, so git does not see them as merged). Keep the release branch; delete it from the remote only if the user asks.
- `tmp/<run>/` stays (gitignored): it is the run's record.
- Tell every agent still idle that it is done.

The final report to the user leads with the outcome (the tag, the `master` commit, CI on both) and then lists: what shipped, item by item against the spec; the decisions taken without asking, with their reasons; the accepted residuals, said plainly; what was deferred and why; the measured costs worth knowing (e.g. a guard's overhead); and the host follow-ups (what a consumer deletes or changes when it bumps). Offer the next step; do not take it.
