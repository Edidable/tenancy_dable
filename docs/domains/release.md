# Release

How the gem is versioned, cut, consumed and checked. The version is [FILE:lib/tenancy_dable/version.rb] (`TenancyDable::VERSION`), which [FILE:tenancy_dable.gemspec] reads, and the release history is [FILE:CHANGELOG.md].

## Versioning policy

The gem follows Semantic Versioning measured against the frozen public contract in `DESIGN.md`: names, signatures, file paths, config defaults, error classes and the documented isolation semantics. [FILE:UPGRADING.md] section 2 holds the policy table. A MAJOR change alters the frozen surface or isolation semantics (removing or renaming a setting or error class, changing a public signature, flipping a default that changes isolation, changing the default-scope decision tree). A MINOR change is a backward-compatible addition (a setting with a safe default, a new `TenancyDable::Error` subclass, a helper, a generator option). A PATCH change is a bug or security fix with no surface change; security fixes ship as PATCH, or MINOR when they must add surface.

[RULE:before 1.0, a `0.MINOR.0` bump may carry breaking changes], and UPGRADING's pre-1.0 caveat tells hosts to pin a tag and review each new minor by hand before bumping it. A release that turns a leak into a raise is a breaking change by this policy even though it only refuses what the contract forbids; the CHANGELOG entry opens by naming the changes that are on by default and can raise in a working host, together with the escape hatch for each.

## The release shape

Releases are cut on `master`. Every release is cut in this shape:

- A merge commit of the release branch into `master`, made with a local `git merge --no-ff <branch>` and titled `Merge branch '<branch>'`; a pull-request merge, titled `Merge pull request #N from <org>/<branch>`, has the same shape. The branch's commits stay as they are, and the gem's release procedure has no pull-request step.
- A single commit titled [CONFIG:Release X.Y.Z] on top of it. It touches exactly two files: [FILE:lib/tenancy_dable/version.rb], where `VERSION` becomes `"X.Y.Z"`, and [FILE:CHANGELOG.md], where the `[Unreleased]` body moves under a new `## [X.Y.Z] - <date>` heading, `[Unreleased]` is reset to `_Nothing yet._`, and the compare links at the bottom are updated: `[Unreleased]` compares `vX.Y.Z...HEAD` and a new `[X.Y.Z]` link compares the previous tag to `vX.Y.Z`.
- An annotated tag [CONFIG:vX.Y.Z] on the Release commit. Its message is one line that starts with the tag name and summarizes the release (`vX.Y.Z: <comma-separated summary>`).

[ABSENCE:no RubyGems publish] exists: the gemspec sets `rubygems_mfa_required`, but no step of the release pushes the gem, and the CI workflow has no release job. [ABSENCE:no GitHub Release object] is created either; the tag and the CHANGELOG are the release. The first compare link in the CHANGELOG points at the tag URL because there is no earlier version to compare.

### Gotcha: `rake release` publishes

[SYMPTOM:running `rake release` pushes the gem to RubyGems and creates a tag of its own]. [CAUSE:the `Rakefile` loads `bundler/gem_tasks`, which defines `rake release`, while the release procedure here is a manual merge, Release commit and annotated tag]. [FIX:cut the release by hand as above]. [RULE:never run `rake release`].

## How hosts consume it

A host pins the gem through a git source on a tag, not through RubyGems: [CONFIG:gem "tenancy_dable", git: "https://github.com/edidable/tenancy_dable", tag: "vX.Y.Z"]. A bump is a new `tag:` followed by `bundle update tenancy_dable`, the install generator re-run (it is idempotent and skips files the host edited), `db:migrate` when new migrations shipped, and the host's own suite as the gate (see UPGRADING section 2). Because the tag is the unit of release, [RULE:a tag is never moved or deleted after a host could have pinned it]; a fix is a new PATCH tag.

`spec.files` in the gemspec lists `lib/**/*`, `README.md`, `CHANGELOG.md` and `LICENSE.txt`, which is what a built gem would contain; `DESIGN.md` and `UPGRADING.md` are repository documents that git consumers see and a packaged gem would not.

## The `[Unreleased]` section

Work that lands before a release is written under `## [Unreleased]`. When the next version is already decided, the section opens with a line of the form [CONFIG:To be released as `X.Y.Z`. See UPGRADING.md#upgrading-to-vXYZ.] so a reader knows which bump the entries belong to; the Release commit replaces that line with the version heading and, when nothing is left, resets the section to `_Nothing yet._`. The CHANGELOG follows Keep a Changelog headings (`Security`, `Added`, `Changed`, and so on). The CHANGELOG and UPGRADING narrate versions by design; `docs/` does not.

## What CI runs

[FILE:.github/workflows/ci.yml] runs on three triggers: [CONFIG:push to branch master], [CONFIG:push of tags matching v*] and [CONFIG:pull_request]. It has two jobs.

The `test` job is a matrix of Ruby lines by Rails lines with `fail-fast: false`; one cell is excluded in the workflow's `exclude:` list, which marks it as not supported together (Rails 7.1 predates Ruby 3.4). Each cell exports `RAILS_VERSION`, runs `bundle install` fresh and then `bundle exec rspec`. The matrix in `.github/workflows/ci.yml`, not any prose, is the list of supported lines, and the gemspec's Ruby floor and framework ranges bound it. `bundler-cache` is off for the matrix because resolution varies per `RAILS_VERSION` while the Gemfile is identical, so a lockfile-keyed cache cannot tell the cells apart.

The `lint` job runs `bundle exec standardrb` with `bundler-cache: true` on the Ruby line named in the workflow. Standard's target is the `ruby_version` of [FILE:.standard.yml], matching the gemspec's floor.

## RAILS_VERSION in the Gemfile

The [FILE:Gemfile] is `gemspec` plus one conditional: when `RAILS_VERSION` is set and is not `default`, it adds `gem "rails", "~> <RAILS_VERSION>.0"`. Unset, or `default`, it resolves the newest Rails the gemspec allows, exactly like a plain local `bundle install`, so the line is inert outside CI. Locally, another Rails line runs through a separate Gemfile so the default lockfile is untouched (see `docs/domains/testing.md`).

## The gitignored lockfile and lint

[FILE:Gemfile.lock] is gitignored, as a library's lockfile is, so CI never reads one: every run resolves the newest `standard` the gemspec allows (the range of the gemspec's `standard` development dependency). The same property means a spec run on a local lockfile proves only that lockfile's dependency set; the matrix proves the supported lines.

### Gotcha: Lint passes locally and fails in CI

[SYMPTOM:`standardrb` is clean on a machine and the lint job reports new offenses]. [CAUSE:the local lockfile pins an older `standard` than the newest the gemspec allows, which the lint job resolves, and newer Standard releases add cops]. [FIX:run `bundle update standard --conservative` before trusting a local lint]. [RULE:a lint result from a stale lockfile proves nothing about CI].

## Before cutting a release

[RULE:the Release commit changes only `version.rb` and `CHANGELOG.md`], so the feature work, its UPGRADING section and its `DESIGN.md` delta are already on `master` through the merge. The contract spec (`docs/domains/testing.md`) must pass against the version being tagged, and the CI matrix must be green on the pushed `master` head before the tag is created and pushed.
