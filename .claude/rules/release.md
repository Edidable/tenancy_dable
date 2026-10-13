---
paths:
  - "lib/tenancy_dable/version.rb"
  - "tenancy_dable.gemspec"
  - "CHANGELOG.md"
  - "UPGRADING.md"
  - "Gemfile"
  - ".github/**"
  - "Rakefile"
  - ".standard.yml"
---
Semver is measured against the frozen contract in `DESIGN.md`; before 1.0 a `0.MINOR.0` may break, so hosts pin a tag and review the next minor by hand.
A change that turns a leak into a raise is breaking: the CHANGELOG entry names what is on by default, what can raise in a working host, and each escape hatch, and UPGRADING gets a section for it.
Pending work goes under `## [Unreleased]`; when the next version is decided it opens with "To be released as `X.Y.Z`." and a link to the UPGRADING section.
The `Release X.Y.Z` commit sits on `master` after the release branch's merge commit (a local `git merge --no-ff`; a pull-request merge has the same shape) and changes exactly two files: `version.rb` and `CHANGELOG.md` (dated heading, `[Unreleased]` reset to `_Nothing yet._`, compare links updated).
The tag is annotated `vX.Y.Z` on that commit, with a one-line message starting with the tag name; never move or delete a tag a host could have pinned.
There is no RubyGems publish and no GitHub Release object: hosts use `git: ..., tag: "vX.Y.Z"`. Never run `rake release`: `Rakefile` loads `bundler/gem_tasks`, so it would publish to RubyGems and create its own tag.
The supported lines are the CI matrix in `.github/workflows/ci.yml` (Ruby by Rails, with the Ruby 3.4 and Rails 7.1 cell excluded); the gemspec's ranges bound it. Changing a range or a cell edits both.
CI must be green on the pushed `master` head before the tag is created and pushed. It runs on push to `master`, on `v*` tags and on pull requests; the `test` matrix runs `bundle exec rspec` per `RAILS_VERSION`, the `lint` job runs `bundle exec standardrb`.
`RAILS_VERSION` in the Gemfile pins a Rails line and is inert when unset or `default`.
`Gemfile.lock` is gitignored, so CI resolves the newest `standard` the gemspec allows: run `bundle update standard --conservative` before trusting a local lint.
Adding a gemspec dependency or changing `spec.files` means checking what a git consumer and a built gem each receive.
Narrative: docs/domains/release.md
