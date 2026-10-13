# Gates

Every gate command, in the order the steps run them. Run them exactly as written; the lead re-runs any gate an agent claims to have passed. The facts behind them (why the lockfile drifts from CI, how the harness database behaves, which Ruby a Rails line needs) are in `docs/domains/testing.md` and `docs/domains/release.md`.

## The suite and the lint

```
bundle exec rspec                       # the whole suite; one process per checkout
bundle exec rspec --seed <n>            # again with other seeds: order dependence shows here
bundle update standard --conservative   # before trusting a local lint (see below)
bundle exec standardrb
```

The lockfile is gitignored, so CI resolves the newest `standard` the gemspec allows while a local lockfile keeps whatever it resolved once. A new cop then fails CI and passes locally. Update `standard` (with `--conservative`, so nothing else moves) at the start of a run and before the release gate, never while an rspec process is running in the same checkout.

## Another Rails line

```
.claude/skills/workflow/scripts/rails-matrix 7.2                     # the whole suite on Rails 7.2
.claude/skills/workflow/scripts/rails-matrix 7.1 spec/scoping        # given paths only
MATRIX_RUBY=3.3.9 .claude/skills/workflow/scripts/rails-matrix 7.1   # with another Ruby
```

The script keeps its own Gemfile and lockfile under `tmp/matrix/`, so the default lockfile is untouched. Rails 7.1 needs a Ruby below 3.4; `MATRIX_RUBY` selects one through the version manager the machine uses (`--help` prints how). The CI matrix (`.github/workflows/ci.yml`) is the authority; the local lines exist so a run finds a Rails-specific break before `master` CI does.

## Throwaway probes

```
bundle exec rspec tmp/<run>/<dir>/<file>_spec.rb -I spec --default-path spec
```

A probe requires `rails_helper` like any spec and lives only under `tmp/` (gitignored). The red-team set (`tmp/<run>/redteam/`) is the regression set from the first verification on; its expected failures are listed in `tmp/<run>/fix-round.md`.

## Integration gate (after every cherry-pick round)

1. `bundle exec rspec` on three seeds, all green.
2. `bundle exec standardrb` clean (after the `standard` update above).
3. `rails-matrix 7.1` (with a Ruby below 3.4) and `rails-matrix 7.2`, green; the current default line is the default bundle.
4. The red-team probe set, failing exactly its expected set (from the first verification on).

## Release-candidate gate (before `rc`, and again on `master` before the tag)

1. The integration gate.
2. `gem build tenancy_dable.gemspec --output tmp/<run>/gem/tenancy_dable-X.Y.Z.gem` succeeds, and the gem contains every new file under `lib/` (locale files, rake tasks and new extensions included):

```
tar -xOf tmp/<run>/gem/tenancy_dable-X.Y.Z.gem data.tar.gz | tar -tz
```

3. Hygiene over the whole release (a path under `.claude/` and the file name `CLAUDE.md` are not attribution, so the first command strips them):

```
git log origin/master..HEAD --format=%B | sed -E 's#\.claude/##g; s#CLAUDE\.md##g' | grep -icE 'co-authored|claude|generated with'   # 0
git diff master...HEAD | grep -inE '<consumer names and domain words from the spec>'        # nothing
git status --short                                                                           # only untracked spec files
```

4. The final verifier's READY on the final commit ([verify.md](verify.md) section 4).

## CI

CI runs on pushes to `master`, on tags and on pull requests (`.github/workflows/ci.yml`); a branch push alone runs nothing, and this workflow opens no pull request, so the first CI run of a release is the pushed `master` head (the merge commit and the `Release X.Y.Z` commit together) and it gates the tag. The lead watches it from a background shell writing to a file, one `gh run watch <id> --exit-status` per run of the commit (`gh run list --commit <sha> --json databaseId -q '.[].databaseId'`). Green on every job, lint included, is the only pass.
