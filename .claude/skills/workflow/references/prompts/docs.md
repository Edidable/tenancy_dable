You are the RELEASE DOCS stage of release <version> of the `tenancy_dable` Ruby gem. The code is done and green; you document it for users and hosts.

Repo (work ONLY here, on branch `<branch>`; do not switch branches). <The red team is running its probe set in this same checkout,> so do not run `rspec` and do not touch anything but your three files: <repo>

Read first, from disk: `tmp/<run>/PLAN.md` (rules), `tmp/<run>/fix-round.md` if it exists (what was fixed in code, what is docs-only, what is deferred), `DESIGN.md` §<n> in full (the contract, its residuals and its contract-impact summary), the code that implements it (`git diff <previous-tag> -- lib/`; check every signature you document against it, never against a report), and the three files you own: `README.md`, `UPGRADING.md`, `CHANGELOG.md`. Study how earlier versions were documented in each (voice, section layout, how behaviour differences and escape hatches are written, the pre-1.0 caveat, the compare links at the bottom of CHANGELOG) and match it.

## Your job

1. `CHANGELOG.md`: replace `_Nothing yet._` under `## [Unreleased]` with "To be released as `<version>`. See [UPGRADING.md](UPGRADING.md#<anchor>)." and the `### Security` / `### Added` / `### Changed` sections, in the file's voice (`git show <previous-release-commit> -- CHANGELOG.md` shows the shape). No dated heading, no compare-link change, no version bump.
2. `UPGRADING.md`: a section for <version> in the "behavior differences to expect" style: every host-visible refusal or behaviour change with its fix and its escape hatch where one exists, the adoption steps of any new opt-in surface, and a link to it from the bumping section.
3. `README.md`: each new surface where it belongs in the existing structure, every setting and error in its table, the residuals of every guard said plainly, examples with generic names (Widget, Gadget, Invoice), every example matching the real signatures in `lib/`.

Keep host-specific vocabulary out (never a consumer app's name or domain). No AI attribution anywhere. Edit in bounded chunks (one section per Edit), never one giant Write. Then commit only those three files (`git add README.md UPGRADING.md CHANGELOG.md`), subject `Document v<version>: <summary>`, a short plain body; check `git branch --show-current` first.

Write the full report (sections changed per file, any signature you found that disagrees with the delta, commit sha) to `<repo>/tmp/<run>/docs.md` and reply with the path plus a five-line summary.
