You are building the FOUNDATION stage of release <version> of the `tenancy_dable` Ruby gem (multi-tenant row scoping for Rails, Combustion harness on SQLite).

Repo (work ONLY here, on branch `<branch>`; do not switch branches): <repo>

Read first, from disk: `tmp/<run>/PLAN.md` (rules every agent follows), `DESIGN.md` §<n> in full (the frozen delta), above all its contract-impact summary, its contract-spec delta and its file-ownership map, which lists exactly which files FOUNDATION owns and whether each is final or an inert stub. Then the existing `lib/` files you will touch, `spec/contract_spec.rb`, `spec/configuration_spec.rb`, `spec/schema_spec.rb`, `spec/support/factories.rb`, `spec/internal/**`. `tmp/<run>/designer.md` is the designer's rationale.

## Your job

Land every FOUNDATION row of the map, nothing else:
- the FINAL shared pieces (new errors, new settings with defaults and `validate!` rules, locale files, railtie wiring, fixtures and factories, the generator template, gemspec development dependencies, the contract and configuration spec updates);
- the INERT STUBS with their final public shape (constants, method names, signatures, visibility, value objects) and no-op behaviour, for every file a workstream will fill in; each stub carries a one-line comment naming the `DESIGN.md` §<n>.x subsection that fills it.

Behaviour must not change yet, except where the map marks a foundation piece as final. After a gemspec change, run `bundle install` and report what resolved.

## Gate (foreground)

`bundle exec rspec` (all green: the existing examples plus your new contract/config/schema assertions) and `bundle exec standardrb` (clean). Then commit only what you changed, naming the paths (`git add -A -- lib spec tenancy_dable.gemspec`; never `git add -A` at the root, never a proposal file or `tmp/`), one commit, subject `Lay the v<version> foundation: <what is final>, and stubs`, a short body listing final vs stubbed. Check `git branch --show-current` is `<branch>` first.

Rules: no AI attribution anywhere (no Co-Authored-By trailer, no "generated with", no mention of Claude or AI in code, comments or the commit). Match the existing code's voice and comment density (frozen_string_literal, Standard style, `DESIGN.md` §<n>.x references in comments). Every gem-raised error descends from `TenancyDable::Error`. Keep host-specific vocabulary out (say "a host"). Edit files in bounded chunks. Run Python or Ruby edits in the foreground; never start a shell command with a bare `cat > file`. If the delta is ambiguous, pick the reading that keeps every file single-owner for the parallel stage, and record it.

Write the full report (files touched, final vs stub per file, deviations from the delta, dependency resolution, final example count, commit sha) to `<repo>/tmp/<run>/foundation.md` and reply with the path plus a five-line summary.
