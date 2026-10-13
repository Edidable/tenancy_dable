# Step 3: Build - foundation, workstreams, integration

The contract is frozen; this step makes it real. It runs in three moves: a serial foundation that lands the shape, parallel workstreams that fill in behaviour, and an integration the lead does alone.

## 1. Foundation

One `sonnet` agent, effort `high` ([references/prompts/foundation.md](references/prompts/foundation.md)), in the main checkout on the run's branch. It lands every FOUNDATION row of the delta's ownership map: the final shared pieces (errors, settings with `validate!`, locale files, railtie wiring, fixtures, factories, the contract spec's new locks, development dependencies) and the inert stubs with their final public shape. Previous behaviour does not change except where the map marks a foundation piece as final.

Gate (the agent runs it; the lead re-runs it): the whole suite green, `standardrb` clean ([gates.md](gates.md)). The agent commits once:

```
Lay the vX.Y.Z foundation: <what is final>, and stubs
```

After a gemspec change, `bundle install` in the main checkout before the worktrees copy the lockfile.

## 2. Workstreams

The lead creates one sibling worktree per workstream, from the foundation commit, and copies the lockfile into each:

```
WT=../tenancy_dable-wt
git worktree add -q "$WT/<name>" -b "<run>/<name>" <foundation-sha>
cp Gemfile.lock "$WT/<name>/"
```

That is all the provisioning a worktree needs here: the harness database is a file under `spec/internal/db/` that each checkout recreates on boot. Smoke one worktree (`bundle exec rspec` there) before spawning.

Then one `sonnet` agent per workstream, all in ONE message so they run concurrently ([references/prompts/workstream.md](references/prompts/workstream.md)). Each prompt names its worktree by absolute path, its delta subsection, its owned files, the spec files it creates and the specs it flips. Each agent runs its own spec files, then the whole suite and `standardrb` in ITS worktree, and commits once on `<run>/<name>`.

While they run, review each commit as it lands (`git diff <foundation-sha> <run>/<name> -- lib/`). A workstream whose full suite fails ONLY on a spec another workstream flips is expected; integration resolves it.

## 3. Integrate

The lead integrates, never an agent. Cherry-pick the workstream commits onto the run's branch in a linear order; never an octopus merge (it makes the history unreadable and cannot be reviewed commit by commit):

```
git cherry-pick <w1-sha> <w2-sha> ...
```

Disjoint ownership means the picks apply cleanly; a conflict means the map was wrong, so resolve it by hand and say so in the report. Then the integration gate ([gates.md](gates.md) -> "Integration gate"): the suite on several seeds, `standardrb` with CI's `standard`, the other Rails lines, and the cross-workstream examples the map named (the example where two workstreams' behaviours meet).

## 4. Close the workstream worktrees

Once every commit is integrated, remove the worktrees (`git worktree remove`) and keep the `<run>/*` branches until the release cleanup. Tell every workstream agent it is done and should not resend.

## 5. Stop point `impl`

With destination `impl`, hand the user the branch, the commits (`git log --oneline master..HEAD`), the gate results and what is not yet verified (step 4 has not run), then end the turn. Otherwise continue to [verify.md](verify.md).

## `solo`

The session builds the foundation and then the items itself, in the same order and with the same commits (foundation, then one commit per item or domain), and runs the same integration gate. No worktrees are needed.
