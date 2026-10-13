# Git reference

Branches, commits, merges and tags. **Binding on every commit, wherever it is made** - the lead, a subagent, a remote session. Pass the "No AI attribution" and "Nothing private" sections word for word to every agent that writes a commit or any text that leaves the machine.

## Branches

- The run's branch: lowercase, hyphenated, descriptive of what the release does (`read-guard-and-tenancy-audit`), never a `<username>/`, `feature/` or `worktree-` prefix. Strip one a tool suggests.
- Workstream and fixer branches: `<run>/<name>` (`v060/w1-scoped-bypass`). They are scratch: cherry-picked onto the run's branch and deleted at release cleanup.
- `master` is the default branch. Work never starts on it; it moves only by the release merge and the `Release X.Y.Z` commit ([release.md](release.md)), or by a fix-forward commit when its CI is red.

## Commit messages

- Read `git log --format=%s master` before the first commit and match it: an imperative, plain-English sentence that says what the change does to the gem ("Guard reads that are not pinned to the current tenant", "Refuse writes into another tenant: insert_all, upsert, records in hand"). Regular hyphen, never an em dash.
- The run's fixed titles: `Freeze the vX.Y.Z contract in DESIGN.md §<n>`, `Lay the vX.Y.Z foundation: <what is final>, and stubs`, `Document vX.Y.Z: <summary>`, `Amend the vX.Y.Z contract to the verified code, and lock it`, `Release X.Y.Z`.
- A body only when it carries a why or a list of what is final vs stubbed that the title cannot; a short plain paragraph, no recap of the diff.
- One commit per step or workstream, not per edit. While a commit is still local, fold a small fix into it (`--amend`, or `--fixup` plus an autosquash).
- Never `--no-verify` unless the user asks.

## No AI attribution - ever

Nothing that leaves the machine references Claude or any AI assistant: no `Co-Authored-By: Claude`, no `Claude-Session:` trailer or session URL, no "Generated with Claude Code", no bot sign-off - in commit messages, tag messages, branch names, issue or PR text, the CHANGELOG, or any doc. Remote sessions append a session trailer by default: strip it, and amend before pushing if it slipped in. Commits use the repo's configured git identity. Before every push, check:

```
git log origin/master..HEAD --format=%B | sed -E 's#\.claude/##g; s#CLAUDE\.md##g' | grep -icE 'co-authored|claude|generated with'   # must print 0
```

## Nothing private

The repository is PUBLIC. A proposal file from a host (`IMPROVEMENT_PROPOSALS*.md`) names that host, its domain and its own vocabulary; none of it enters a tracked file, a commit message or a tag. Say "a host" or "a production consumer". The proposal files themselves stay untracked (they are gitignored): never `git add -A` at the repo root, always name the paths (`git add -A -- lib spec`, `git add DESIGN.md`). Before every push, grep the release diff for the consumer's names and domain words (the lead knows them from the spec) and for personal names.

## Merging and tagging

- Workstreams reach the run's branch by **cherry-pick, in a linear order**, never an octopus merge. If one slipped in, reset the branch to the commit before it (the workstream commits are safe on their own branches) and cherry-pick.
- The branch reaches `master` by a local `git merge --no-ff`, after rebasing it onto `master` if `master` moved; no pull request is opened. The merge commit and the `Release X.Y.Z` commit are pushed together, and that pushed `master` head is the CI gate.
- Tags are **annotated**, `vX.Y.Z`, with a one-line message `vX.Y.Z: <what the release adds>`, created and pushed only after the pushed `master` head is green on every cell of the CI matrix, on exactly that commit.
- **Never force-push `master`**, never move or delete a pushed tag. A wrong release is fixed forward with a new patch version.
- **Never run `rake release`**: `Rakefile` loads `bundler/gem_tasks`, so it would publish the gem to RubyGems and create its own tag. A release is cut by hand, as [release.md](release.md) describes.
- `git push --force-with-lease` (never bare `--force`) on the run's branch only, and only if it was pushed and then rebased.
